import json, os, random, datetime, traceback, re, mimetypes, sys, time, hmac, hashlib, base64, secrets
import urllib.request, urllib.parse
from urllib.error import HTTPError, URLError
import boto3

"""
DFJ Document-Share Lambda
- Journal OTP (legacy): /otp-send, /otp-verify (+ e,t links)
- Identifier OTP (new): /identifier/request-otp, /identifier/verify-otp (+ session)
- Identifier-protected: /identifier/list, /identifier/doc-url, /identifier/approve
- Journal-protected:    /doc-list, /doc-url, /approve
- Chat remains journal-scoped
"""

# ===================== ENV =====================
AWS_REGION  = os.environ.get("AWS_REGION", "eu-north-1")
DOCS_BUCKET = os.environ.get("DOCS_BUCKET") or os.environ.get("BUCKET", "dfj-docs-test")

SF_LOGIN_URL     = os.environ.get("SF_LOGIN_URL", "https://test.salesforce.com")
SF_CLIENT_ID     = os.environ.get("SF_CLIENT_ID")
SF_CLIENT_SECRET = os.environ.get("SF_CLIENT_SECRET")
SF_REFRESH_TOKEN = os.environ.get("SF_REFRESH_TOKEN")

DEBUG_ALLOW_IDENTIFIER_DOCURL = (os.environ.get("DEBUG_ALLOW_IDENTIFIER_DOCURL", "false").lower() == "true")
SESSION_HMAC_SECRET = os.environ.get("SESSION_HMAC_SECRET", "")
SESSION_TTL_SECONDS = int(os.environ.get("URL_TTL_SECONDS", "900"))  # default 15 min if unset

# AI Chatbot configuration
AI_ENABLED = (os.environ.get("AI_ENABLED", "true").lower() == "true")
DYNAMODB_TEXT_CACHE_TABLE = os.environ.get("DYNAMODB_TEXT_CACHE_TABLE", "dfj-pdf-text-cache")
BEDROCK_MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "us.anthropic.claude-3-5-haiku-20241022-v1:0")
BEDROCK_REGION = os.environ.get("BEDROCK_REGION", "us-east-1")

ALLOWED_ORIGINS = {
    "https://dfj.lightning.force.com",
    "https://dfj.my.salesforce.com",
    "https://dfj--itdev.sandbox.lightning.force.com",
    "https://dfj--itdev.sandbox.my.salesforce.com",
    "https://dfj--itdevops.sandbox.lightning.force.com",
    "https://dfj--itdevops.sandbox.my.salesforce.com",
    "https://dfj--itdevopsi.sandbox.lightning.force.com",
    "https://dfj--itdevopsi.sandbox.my.salesforce.com",
    "https://dfj--penneo.sandbox.lightning.force.com",
    "https://dfj--penneo.sandbox.my.salesforce.com",
    "http://localhost:3000",
    "http://localhost:5173",
    "http://localhost:8000",
    "http://localhost:8080",
    "https://dok.dinfamiliejurist.dk",
    "https://dok.dinfamiljejurist.se",
    "https://docs.hereslaw.ie",
    "https://dok-test.dinfamiliejurist.dk",
    "https://dok-test.dinfamiljejurist.se",
    "https://docs-test.hereslaw.ie",
}

# Optional mapping for S3 prefixes by Market Unit.
try:
    _S3_PREFIX_MAP = json.loads(os.environ.get("S3_PREFIX_MAP", "") or "{}")
except Exception:
    _S3_PREFIX_MAP = {}

_DEFAULT_PREFIX_MAP = {
    "DFJ_DK": "dk/customer-documents",
    "FA_SE":  "se/customer-documents",
    "Ireland":"ie/customer-documents",
}
_FALLBACK_PREFIX = "customer-documents"


def s3_base_prefix_for_market(market_unit: str) -> str:
    mu = (market_unit or "").strip()
    if mu in _S3_PREFIX_MAP:
        return _S3_PREFIX_MAP[mu]
    return _DEFAULT_PREFIX_MAP.get(mu, _FALLBACK_PREFIX)

# ===================== SOQL SAFE HELPERS (NEW) =====================

def soql_escape(s: str) -> str:
    # Escape single quotes for SOQL string literals
    return (s or "").replace("'", "\\'")

def soql_in_list(values):
    # Build a comma-separated '...','...' list for SOQL IN (...)
    return ", ".join("'" + soql_escape(v) + "'" for v in (values or []) if v)


# -------- OTP__c constants (hard-coded, no new envs) --------
OTP_PURPOSE = "DocumentPortal"  # distinct from cancellation portal

def _get_header(event, name: str) -> str:
    hdrs = (event.get("headers") or {})
    for k, v in hdrs.items():
        if k.lower() == name.lower():
            return str(v or "")
    return ""

def detect_brand(event, hinted=None) -> str:
    # Prefer explicit hint (e.g. ?brand=) then Origin/Referer/Host
    qs = event.get("rawQueryString") or ""
    try:
        q = dict(urllib.parse.parse_qsl(qs))
        if (q.get("brand") or "").lower() in ("dk","se","ie"):
            return (q.get("brand") or "dk").lower()
    except Exception:
        pass
    blob = " ".join([
        str(hinted or ""),
        _get_header(event, "x-forwarded-host"),
        _get_header(event, "origin"),
        _get_header(event, "referer"),
        _get_header(event, "host"),
    ]).lower()
    if "dinfamiliejurist.dk" in blob:  return "dk"
    if "dinfamiljejurist.se" in blob:  return "se"
    if "hereslaw.ie" in blob:          return "ie"
    return "dk"

def _identifier_exists(instance_url, org_token, email: str = "", phone: str = "") -> bool:
    try:
        if phone:
            phone_norm = normalize_phone_basic(phone)
            esc_vals = ["'" + v.replace("'", "\\'") + "'" for v in phone_variants_for_match(phone_norm)]
            in_clause = ", ".join(esc_vals) if esc_vals else "''"
            soql = (
                "SELECT COUNT() FROM Shared_Document__c WHERE "
                "(Journal__r.Account__r.Phone_Formatted__c = '" + phone_norm.replace("'", "\\'") + "' "
                "OR (Journal__r.Account__r.Is_Spouse_Shared_Document_Recipient__pc = true "
                "AND Journal__r.Account__r.Spouse_Phone__pc IN (" + in_clause + ")))"
            )
        else:
            e = (email or "").lower().replace("'", "\\'")
            soql = (
                "SELECT COUNT() FROM Shared_Document__c WHERE "
                "(Journal__r.Account__r.PersonEmail = '" + e + "' "
                "OR (Journal__r.Account__r.Is_Spouse_Shared_Document_Recipient__pc = true "
                "AND Journal__r.Account__r.Spouse_Email__pc = '" + e + "'))"
            )
        count = int(salesforce_query(instance_url, org_token, soql).get("totalSize", 0))
        return count > 0
    except Exception:
        return False


# ===================== RESP / CORS =====================

def _cors_origin(event):
    try:
        hdrs = event.get("headers") or {}
        origin = hdrs.get("origin") or hdrs.get("Origin")
        if origin in ALLOWED_ORIGINS:
            return origin
    except Exception:
        pass
    return "*"  # safe default for our usage (no cookies)

def resp(event, status, body, content_type="application/json"):
    payload = body if isinstance(body, str) else json.dumps(body)
    headers = {
        "Content-Type": content_type,
        "Access-Control-Allow-Origin": _cors_origin(event),
        "Access-Control-Allow-Headers": "Content-Type,Authorization",
        "Access-Control-Allow-Methods": "POST,GET,OPTIONS",
        "Vary": "Origin",  # UPDATED: aid caches
    }
    return {"statusCode": status, "headers": headers, "body": payload}

def log(*args):
    print(*args, file=sys.stdout, flush=True)

def handle_diag_net(event):
    try:
        urllib.request.urlopen("https://test.salesforce.com", timeout=3)
        return resp(event, 200, {"ok": True, "https_to_salesforce": True})
    except Exception as e:
        return resp(event, 200, {"ok": False, "https_to_salesforce": False, "error": repr(e)})

# ===================== SALESFORCE AUTH =====================

def get_org_token():
    data = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "client_id": SF_CLIENT_ID or "",
        "client_secret": SF_CLIENT_SECRET or "",
        "refresh_token": SF_REFRESH_TOKEN or "",
    }).encode("utf-8")
    url = f"{SF_LOGIN_URL}/services/oauth2/token"
    req = urllib.request.Request(url, data=data, method="POST")
    with urllib.request.urlopen(req, timeout=10) as r:
        out = json.loads(r.read().decode("utf-8"))
        if "access_token" not in out or "instance_url" not in out:
            log("SF token success but missing fields:", out)
            raise RuntimeError("Salesforce token response missing fields")
        return out["access_token"], out["instance_url"]

# ===================== SF HELPERS =====================

def salesforce_query(instance_url, org_token, soql):
    url = f"{instance_url}/services/data/v61.0/query?q={urllib.parse.quote(soql)}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {org_token}"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read().decode("utf-8"))
    except HTTPError as e:
        # NEW: Log Salesforce error response
        try:
            error_body = e.read().decode("utf-8")
            log("SALESFORCE_ERROR:", e.code, error_body)
        except Exception:
            log("SALESFORCE_ERROR:", e.code, "(no body)")
        raise

def salesforce_patch(instance_url, org_token, sobject, rec_id, payload):
    url = f"{instance_url}/services/data/v61.0/sobjects/{sobject}/{rec_id}"
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        method="PATCH",
        headers={"Authorization": f"Bearer {org_token}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=15):
        return True

def salesforce_insert(instance_url, org_token, sobject, payload):
    url = f"{instance_url}/services/data/v61.0/sobjects/{sobject}"
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        method="POST",
        headers={"Authorization": f"Bearer {org_token}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))["id"]

# ===================== S3 PRESIGN =====================
_s3 = boto3.client("s3", region_name=AWS_REGION)

# AI Chatbot clients (lazy-initialized)
_dynamodb = None
_text_cache_table = None
_bedrock_client = None

def _get_text_cache_table():
    """Lazy-initialize DynamoDB table for text caching."""
    global _dynamodb, _text_cache_table
    if _text_cache_table is None:
        _dynamodb = boto3.resource('dynamodb', region_name=AWS_REGION)
        _text_cache_table = _dynamodb.Table(DYNAMODB_TEXT_CACHE_TABLE)
    return _text_cache_table

def _get_bedrock_client():
    """Lazy-initialize Bedrock client."""
    global _bedrock_client
    if _bedrock_client is None:
        _bedrock_client = boto3.client('bedrock-runtime', region_name=BEDROCK_REGION)
    return _bedrock_client

def s3_presign_get(bucket, key, expires=600):
    return _s3.generate_presigned_url(
        ClientMethod="get_object",
        Params={
            "Bucket": bucket,
            "Key": key,
            "ResponseContentDisposition": f'inline; filename="{os.path.basename(key)}"',
            "ResponseContentType": "application/pdf",
        },
        ExpiresIn=int(expires),
    )

# ===================== BASIC NORMALIZATION =====================

def normalize_phone_basic(raw: str) -> str:
    if not raw:
        return raw
    s = raw.strip()
    for ch in (" ", "-", "(", ")"):
        s = s.replace(ch, "")
    if s.startswith("00"):
        s = "+" + s[2:]
    if s.startswith("+"):
        return s
    if s.startswith("45") or s.startswith("46") or s.startswith("353"):
        return "+" + s
    return s

def phone_variants_for_match(p: str):
    vals = set()
    if not p:
        return []
    vals.add(p)
    if p.startswith("+"):
        vals.add(p[1:])           # without +
        vals.add("00" + p[1:])    # 00-country
    return [v for v in vals if v]

# ===================== DATETIME PARSING (ROBUST) =====================

def _parse_sf_datetime(raw: str):
    """
    Accepts common Salesforce datetime shapes:
      - 2025-10-17T11:10:40Z
      - 2025-10-17T11:10:40.000Z
      - 2025-10-17T11:10:40.000+0000
      - 2025-10-17T13:10:40.000+0200 (any ±HHMM)
    Returns an aware UTC datetime, or None if unparseable.
    """
    if not raw:
        return None
    s = raw.strip()

    # Convert trailing +HHMM/-HHMM to +HH:MM/-HH:MM so fromisoformat can parse
    m = re.search(r'([+-])(\d{2})(\d{2})$', s)
    if m:
        s = s[:-5] + f"{m.group(1)}{m.group(2)}:{m.group(3)}"

    # Handle 'Z' (UTC) by replacing with +00:00
    if s.endswith('Z'):
        s = s[:-1] + '+00:00'

    # Some orgs/fields can store a space instead of 'T'
    if ' ' in s and 'T' not in s:
        s = s.replace(' ', 'T', 1)

    try:
        dt = datetime.datetime.fromisoformat(s)
        if dt.tzinfo is None:
            # If somehow naive, assume UTC
            dt = dt.replace(tzinfo=datetime.timezone.utc)
        return dt.astimezone(datetime.timezone.utc)
    except Exception:
        pass

    # Fallbacks for exact Z formats
    for fmt in ("%Y-%m-%dT%H:%M:%S.%fZ", "%Y-%m-%dT%H:%M:%SZ"):
        try:
            return datetime.datetime.strptime(raw.strip(), fmt).replace(tzinfo=datetime.timezone.utc)
        except Exception:
            continue

    return None

# ===================== JOURNAL AUTH (legacy) =====================

def auth_journal(external_id: str, access_token: str):
    if not external_id or not access_token:
        log("auth_journal: missing externalId or accessToken")
        return None
    org_token, instance_url = get_org_token()
    esc_ext = external_id.replace("'", "\\'")
    soql = (
        "SELECT Id, Access_Token__c "
        "FROM Journal__c "
        f"WHERE External_ID__c = '{esc_ext}' "
        "LIMIT 1"
    )
    recs = salesforce_query(instance_url, org_token, soql).get("records", [])
    if not recs:
        log("auth_journal: no journal for externalId", external_id)
        return None
    row = recs[0]
    if (row.get("Access_Token__c") or "") != access_token:
        log("auth_journal: token mismatch for externalId", external_id)
        return None
    return {"id": row["Id"], "externalId": external_id}

# ===================== SESSION (identifier) =====================

def _b64u(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode("ascii")

def _b64u_dec(s: str) -> bytes:
    s += "=" * (-len(s) % 4)
    return base64.urlsafe_b64decode(s.encode("ascii"))

def make_session(identifier_type: str, identifier_value: str, ttl=SESSION_TTL_SECONDS) -> str:
    if not SESSION_HMAC_SECRET:
        raise RuntimeError("Missing SESSION_HMAC_SECRET")
    now = int(time.time())
    payload = {
        "iat": now,
        "exp": now + int(ttl),
        "typ": identifier_type,   # "email" | "phone"
        "sub": identifier_value,  # normalized (email lower, phone normalized)
        "nonce": secrets.token_hex(8)
    }
    body = _b64u(json.dumps(payload, separators=(",",":")).encode("utf-8"))
    sig  = _b64u(hmac.new(SESSION_HMAC_SECRET.encode("utf-8"), body.encode("ascii"), hashlib.sha256).digest())
    return body + "." + sig

def verify_session(token: str) -> dict:
    if not token or "." not in token:
        raise RuntimeError("bad token")
    body, sig = token.split(".", 1)
    expect = _b64u(hmac.new(SESSION_HMAC_SECRET.encode("utf-8"), body.encode("ascii"), hashlib.sha256).digest())
    if not hmac.compare_digest(expect, sig):
        raise RuntimeError("bad signature")
    payload = json.loads(_b64u_dec(body).decode("utf-8"))
    if int(time.time()) > int(payload.get("exp", 0)):
        raise RuntimeError("expired")
    return payload

def get_bearer(event) -> str:
    hdrs = event.get("headers") or {}
    auth = hdrs.get("authorization") or hdrs.get("Authorization") or ""
    if auth.lower().startswith("bearer "):
        return auth.split(" ", 1)[1].strip()
    return ""

# ===================== OTP (journal) =====================

def handle_otp_send(event, event_json):
    data = event_json or {}
    external_id = (data.get("externalId") or "").strip()
    if not external_id:
        return resp(event, 400, {"error": "Missing externalId"})
    org_token, instance_url = get_org_token()
    esc_ext = external_id.replace("'", "\\'")
    q = "SELECT Id FROM Journal__c WHERE External_ID__c = '" + esc_ext + "' LIMIT 1"
    recs = salesforce_query(instance_url, org_token, q).get("records", [])
    if not recs:
        return resp(event, 404, {"error": "Not found"})
    journal_id = recs[0]["Id"]
    otp = f"{random.randint(0, 999999):06d}"
    expires = (datetime.datetime.utcnow() + datetime.timedelta(minutes=10)).strftime("%Y-%m-%dT%H:%M:%SZ")
    payload = {"OTP_Code__c": otp, "OTP_Expires__c": expires}
    salesforce_patch(instance_url, org_token, "Journal__c", journal_id, payload)
    return resp(event, 200, {"ok": True})

def handle_otp_verify(event, event_json):
    data = event_json or {}
    external_id = (data.get("externalId") or "").strip()
    otp = (data.get("otp") or "").strip()
    if not external_id or not otp:
        return resp(event, 400, {"error": "Missing externalId or otp"})
    org_token, instance_url = get_org_token()
    esc_ext = external_id.replace("'", "\\'")
    soql = (
        "SELECT Id, OTP_Code__c, OTP_Expires__c "
        "FROM Journal__c "
        f"WHERE External_ID__c = '{esc_ext}' "
        "LIMIT 1"
    )
    recs = salesforce_query(instance_url, org_token, soql).get("records", [])
    if not recs:
        return resp(event, 404, {"error": "Not found"})
    row = recs[0]
    if otp != (row.get("OTP_Code__c") or ""):
        return resp(event, 200, {"ok": False, "error": "Invalid code"})
    try:
        raw_exp = (row.get("OTP_Expires__c") or "").strip()
        exp_dt  = _parse_sf_datetime(raw_exp)
        now_utc = datetime.datetime.now(datetime.timezone.utc)
        if not (exp_dt and now_utc <= exp_dt):
            return resp(event, 200, {"ok": False, "error": "Code expired"})
    except Exception:
        return resp(event, 200, {"ok": False, "error": "Code expired"})
    return resp(event, 200, {"ok": True})

# ===================== Identifier helpers (find journals) =====================

def _find_journal_ids_by_email(instance_url, org_token, email: str):
    esc = email.replace("'", "\\'")
    soql = (
        "SELECT Journal__c "
        "FROM Shared_Document__c "
        "WHERE Journal__r.Account__r.PersonEmail = '" + esc + "' "
        "   OR (Journal__r.Account__r.Is_Spouse_Shared_Document_Recipient__pc = true "
        "       AND Journal__r.Account__r.Spouse_Email__pc = '" + esc + "') "
        "GROUP BY Journal__c "
        "LIMIT 200"
    )
    recs = salesforce_query(instance_url, org_token, soql).get("records", [])
    out = []
    for r in recs:
        jid = r.get("Journal__c") or r.get("Expr0") or r.get("expr0")
        if jid: out.append(jid)
    return out

def _find_journal_ids_by_phone(instance_url, org_token, phone_norm: str):
    variants = phone_variants_for_match(phone_norm)
    if phone_norm not in variants: variants.append(phone_norm)
    in_clause = ", ".join("'" + v.replace("'", "\\'") + "'" for v in variants)
    soql = (
        "SELECT Journal__c "
        "FROM Shared_Document__c "
        "WHERE Journal__r.Account__r.Phone_Formatted__c = '" + phone_norm.replace("'", "\\'") + "' "
        "   OR (Journal__r.Account__r.Is_Spouse_Shared_Document_Recipient__pc = true "
        "       AND Journal__r.Account__r.Spouse_Phone__pc IN (" + (in_clause or "''") + ")) "
        "GROUP BY Journal__c "
        "LIMIT 200"
    )
    recs = salesforce_query(instance_url, org_token, soql).get("records", [])
    out = []
    for r in recs:
        jid = r.get("Journal__c") or r.get("Expr0") or r.get("expr0")
        if jid: out.append(jid)
    return out

# ===================== Identifier OTP (new) =====================

def handle_identifier_request_otp(event, data):
    raw_email = (data.get("email") or "").strip()
    raw_phone = (data.get("phone") or "").strip()
    has_email = bool(raw_email)
    has_phone = bool(raw_phone)
    if not (has_email ^ has_phone):
        return resp(event, 400, {"error": "Provide exactly one of: email OR phone"})

    try:
        org_token, instance_url = get_org_token()

        # --- 1) existence check (no enumeration in response) ---
        if has_email:
            email = raw_email.lower()
            if "@" not in email or "." not in email.split("@")[-1]:
                return resp(event, 200, {"ok": True})  # soft success
            exists = _identifier_exists(instance_url, org_token, email=email)
        else:
            phone = normalize_phone_basic(raw_phone)
            if not any(ch.isdigit() for ch in phone):
                return resp(event, 200, {"ok": True})
            exists = _identifier_exists(instance_url, org_token, phone=phone)

        # --- 2) build OTP__c (ALWAYS CREATE a row, even if no match) ---
        brand = detect_brand(event)
        now = datetime.datetime.utcnow()
        expires = (now + datetime.timedelta(minutes=5)).strftime("%Y-%m-%dT%H:%M:%SZ")
        code = f"{random.randint(0, 999999):06d}"
        identifier_type  = "Email" if has_email else "Phone"
        identifier_value = (raw_email.lower() if has_email else normalize_phone_basic(raw_phone))
        channel = "Email" if has_email else "SMS"

        # count prior sends for Resend_Count__c
        try:
            soql_cnt = (
                "SELECT COUNT() FROM OTP__c WHERE "
                f"Purpose__c = '{OTP_PURPOSE}' AND "
                f"Brand__c = '{brand}' AND "
                f"Identifier_Type__c = '{identifier_type}' AND "
                f"Identifier_Value__c = '{soql_escape(identifier_value)}'"
            )
            prev_count = int(salesforce_query(instance_url, org_token, soql_cnt).get("totalSize", 0))
        except Exception:
            prev_count = 0

        unique_key = f"{OTP_PURPOSE}|{identifier_type}|{identifier_value}|{brand}|{secrets.token_hex(8)}"

        fields = {
            "Key__c": unique_key,
            "Brand__c": brand,
            "Purpose__c": OTP_PURPOSE,
            "Resource_Type__c": "Shared_Document__c",
            "Identifier_Type__c": identifier_type,
            "Identifier_Value__c": identifier_value,
            "Channel__c": channel,

            "Code__c": code,
            "Status__c": "Pending",
            "Sent_At__c": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "Expires_At__c": expires,
            "Attempt_Count__c": 0,
            "Resend_Count__c": prev_count,
        }

        try:
            rec_id = salesforce_insert(instance_url, org_token, "OTP__c", fields)
            log("OTP__c created", rec_id, identifier_type, identifier_value, brand, "exists:", exists)
        except Exception as e:
            log("OTP__c create error:", repr(e))

        # Always soft-success (whether match exists or not)
        return resp(event, 200, {"ok": True})

    except Exception as e:
        log("identifier_request_otp error:", repr(e))
        # still soft-success to avoid leaking anything
        return resp(event, 200, {"ok": True})

def handle_identifier_verify_otp(event, data):
    raw_email = (data.get("email") or "").strip()
    raw_phone = (data.get("phone") or "").strip()
    otp       = (data.get("otp")   or "").strip()
    if not (otp.isdigit() and len(otp) == 6):
        return resp(event, 200, {"ok": False})

    has_email = bool(raw_email)
    has_phone = bool(raw_phone)
    if not (has_email ^ has_phone):
        return resp(event, 200, {"ok": False})

    try:
        org_token, instance_url = get_org_token()
        brand = detect_brand(event)
        if has_email:
            identifier_type  = "Email"
            identifier_value = raw_email.lower()
        else:
            identifier_type  = "Phone"
            identifier_value = normalize_phone_basic(raw_phone)

        # DEBUG input snapshot
        log("VERIFY_DEBUG_IN", {
            "brand": brand,
            "type": identifier_type,
            "value": identifier_value,
            "otp": otp
        })

        # Most recent pending OTP for this tuple
        soql = (
            "SELECT Id, Code__c, Expires_At__c, Status__c, Attempt_Count__c "
            "FROM OTP__c WHERE "
            f"Purpose__c = '{OTP_PURPOSE}' AND "
            f"Brand__c = '{brand}' AND "
            f"Identifier_Type__c = '{identifier_type}' AND "
            f"Identifier_Value__c = '{soql_escape(identifier_value)}' AND "
            "Status__c = 'Pending' "
            "ORDER BY CreatedDate DESC "
            "LIMIT 1"
        )
        recs = salesforce_query(instance_url, org_token, soql).get("records", [])
        if not recs:
            return resp(event, 200, {"ok": False})

        row = recs[0]
        # DEBUG record snapshot
        log("VERIFY_DEBUG_REC2", {
            "id": row.get("Id"),
            "code": (row.get("Code__c") or ""),
            "expires": (row.get("Expires_At__c") or ""),
            "status": (row.get("Status__c") or ""),
            "attempts": (row.get("Attempt_Count__c") or 0)
        })

        attempts = int(row.get("Attempt_Count__c") or 0)

        # expiry (robust)
        raw_exp = (row.get("Expires_At__c") or "").strip()
        exp_dt  = _parse_sf_datetime(raw_exp)
        now_utc = datetime.datetime.now(datetime.timezone.utc)
        not_expired = (exp_dt is not None) and (now_utc <= exp_dt)

        # match + status
        code_matches = (otp == (row.get("Code__c") or "").strip())
        status = (row.get("Status__c") or "Pending").strip()

        # DEBUG comparison snapshot
        log("VERIFY_DEBUG_CHECK", {
            "now_utc": now_utc.isoformat(),
            "raw_exp": raw_exp,
            "parsed_exp_utc": (exp_dt.isoformat() if exp_dt else None),
            "not_expired": not_expired
        })
        log("VERIFY_DEBUG_MATCH", {
            "code_matches": code_matches,
            "status": status,
            "attempts": attempts
        })

        if code_matches and not_expired and status == "Pending":
            try:
                salesforce_patch(instance_url, org_token, "OTP__c", row["Id"], {
                    "Status__c": "Verified",
                    "Verified_At__c": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "Attempt_Count__c": attempts + 1
                })
            except Exception:
                pass

            # Issue the same session token your SPA already uses
            token = make_session("email" if has_email else "phone", identifier_value, ttl=SESSION_TTL_SECONDS)
            return resp(event, 200, {"ok": True, "session": token})

        # failed attempt → increment attempts (best-effort)
        try:
            salesforce_patch(instance_url, org_token, "OTP__c", row["Id"], {
                "Attempt_Count__c": attempts + 1
            })
        except Exception:
            pass
        return resp(event, 200, {"ok": False})

    except Exception as e:
        log("identifier_verify_otp error:", repr(e))
        return resp(event, 200, {"ok": False})

# ===================== Client Impersonation Login =====================

def handle_impersonation_login(event, data):
    """
    POST /impersonation/login
    Body: { "token": "64-char-hex-token" }
    Returns: { "ok": true, "session": "...", "journalId": "...", "journalName": "...", "allowApprove": true }
    
    SECURITY: Token can only be used once. After first use, it is immediately invalidated.
    """
    token = (data.get("token") or "").strip()
    if not token:
        return resp(event, 400, {"error": "Missing token"})

    try:
        org_tok, inst = get_org_token()
        safe = soql_escape(token)
        soql = (
            "SELECT Id, Journal__c, Journal__r.Name, Allow_Approve__c, Expires_At__c, Used_At__c, Is_Revoked__c "
            f"FROM Client_Impersonation__c WHERE Token__c = '{safe}' LIMIT 1"
        )
        recs = salesforce_query(inst, org_tok, soql).get("records", [])
        if not recs:
            return resp(event, 200, {"ok": False, "error": "Invalid or expired token"})

        row = recs[0]
        
        # SECURITY: Check if token has been revoked
        if row.get("Is_Revoked__c"):
            log("impersonation_login: Token revoked:", row.get("Id"))
            return resp(event, 200, {"ok": False, "error": "This link has been revoked"})
        
        # SECURITY: Check if token has already been used
        if row.get("Used_At__c"):
            log("impersonation_login: Token already used:", row.get("Id"))
            return resp(event, 200, {"ok": False, "error": "This link has already been used"})
        
        # Check expiry (reuse robust parser)
        exp_dt = _parse_sf_datetime(row.get("Expires_At__c") or "")
        now_utc = datetime.datetime.now(datetime.timezone.utc)
        if not (exp_dt and now_utc <= exp_dt):
            return resp(event, 200, {"ok": False, "error": "Token expired"})

        # Calculate TTL (min of link expiry and normal session TTL)
        ttl = min(SESSION_TTL_SECONDS, int((exp_dt - now_utc).total_seconds()))

        # SECURITY: Mark token as used BEFORE creating session
        # This ensures the token can't be reused even if session creation fails
        source_ip = (event.get("requestContext", {}).get("http", {}) or {}).get("sourceIp")
        try:
            salesforce_patch(inst, org_tok, "Client_Impersonation__c", row["Id"], {
                "Used_At__c": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
                "Used_By_IP__c": source_ip or ""
            })
        except Exception as e:
            log("impersonation_login: Failed to mark token as used:", repr(e))
            return resp(event, 500, {"error": "Failed to validate token"})

        # Create session with impersonation claims (no identifier needed)
        sess = make_session(
            "impersonation", "N/A", ttl=ttl,  # Dummy identifier (unused)
            role="impersonation",
            allowApprove=bool(row.get("Allow_Approve__c")),
            jid=row.get("Journal__c"),
            msid=row.get("Id")  # Client_Impersonation__c record ID for audit
        )

        return resp(event, 200, {
            "ok": True,
            "session": sess,
            "journalId": row.get("Journal__c"),
            "journalName": (row.get("Journal__r") or {}).get("Name") or "",
            "allowApprove": bool(row.get("Allow_Approve__c"))
        })
    except Exception as e:
        log("impersonation_login error:", repr(e))
        return resp(event, 500, {"error": "Server error"})

# ===================== Identifier List / URL (session required) =====================

def _require_identifier_session(event, provided_email: str, provided_phone: str):
    token = get_bearer(event)
    if not token:
        return (None, resp(event, 401, {"error": "Missing session"}))
    try:
        payload = verify_session(token)
    except Exception as e:
        return (None, resp(event, 401, {"error": "Invalid session"}))
    typ = payload.get("typ")
    sub = payload.get("sub") or ""
    if provided_email:
        email = provided_email.lower().strip()
        if typ != "email" or sub != email:
            return (None, resp(event, 403, {"error": "Forbidden"}))
        return ({"typ":"email","sub":email}, None)
    else:
        phone = normalize_phone_basic(provided_phone)
        if typ != "phone" or sub != phone:
            return (None, resp(event, 403, {"error": "Forbidden"}))
        return ({"typ":"phone","sub":phone}, None)

def handle_identifier_list(event, event_json):
    data = event_json or {}
    raw_email = (data.get("email") or "").strip()
    raw_phone = (data.get("phone") or "").strip()
    journal_id = (data.get("journalId") or "").strip()  # NEW: optional filter by journal
    has_email = bool(raw_email)
    has_phone = bool(raw_phone)
    
    # IMPERSONATION: Check if session has jid claim (journal-scoped session)
    token = get_bearer(event)
    sess = None
    if token:
        try:
            sess = verify_session(token)
        except Exception:
            return resp(event, 401, {"error": "Invalid session"})
    
    # For impersonation mode (jid claim exists), we don't need email/phone
    if sess and sess.get("jid"):
        journal_id = sess["jid"]
    else:
        # Normal identifier mode: require exactly one of email OR phone
        if not (has_email ^ has_phone):
            return resp(event, 400, {"error": "Provide exactly one of: email OR phone"})
        
        # Require a verified session
        sess, err = _require_identifier_session(event, raw_email if has_email else "", raw_phone if has_phone else "")
        if err: return err

    try:
        org_token, instance_url = get_org_token()
    except Exception as e:
        log("identifier_list oauth error:", repr(e))
        return resp(event, 500, {"error": "Salesforce OAuth failed"})

    # Build base SOQL
    # For impersonation mode with jid claim, we filter only by journal (no email/phone needed)
    if sess and sess.get("jid"):
        # Impersonation mode: filter only by journal ID
        where_clause = f"WHERE Is_Newest_Version__c = true AND Journal__c = '{soql_escape(journal_id)}'"
    elif has_email:
        email = raw_email.lower()
        esc = email.replace("'", "\\'")
        where_clause = (
            "WHERE Is_Newest_Version__c = true AND ("
            "      Journal__r.Account__r.PersonEmail = '" + esc + "' "
            "   OR (Journal__r.Account__r.Is_Spouse_Shared_Document_Recipient__pc = true "
            "       AND Journal__r.Account__r.Spouse_Email__pc = '" + esc + "')"
            ")"
        )
        # Add journal filter if provided
        if journal_id:
            where_clause += f" AND Journal__c = '{soql_escape(journal_id)}'"
    else:
        phone = normalize_phone_basic(raw_phone)
        esc_vals = ["'" + v.replace("'", "\\'") + "'" for v in phone_variants_for_match(phone)]
        in_clause = ", ".join(esc_vals) if esc_vals else "''"
        where_clause = (
            "WHERE Is_Newest_Version__c = true AND ("
            "      Journal__r.Account__r.Phone_Formatted__c = '" + phone.replace("'", "\\'") + "' "
            "   OR (Journal__r.Account__r.Is_Spouse_Shared_Document_Recipient__pc = true "
            "       AND Journal__r.Account__r.Spouse_Phone__pc IN (" + in_clause + "))"
            ")"
        )
        # Add journal filter if provided
        if journal_id:
            where_clause += f" AND Journal__c = '{soql_escape(journal_id)}'"
    
    soql = (
        "SELECT Id, Name, Version__c, Status__c, S3_Key__c, Is_Newest_Version__c, "
        "       Document_Type__c, Market_Unit__c, Sent_Date__c, First_Viewed__c, Last_Viewed__c, "
        "       Journal__c, Journal__r.Name, Journal__r.First_Draft_Sent__c, Sort_Order__c, "
        "       Is_Approval_Blocked__c "
        "FROM Shared_Document__c "
        + where_clause + " "
        "ORDER BY Sort_Order__c NULLS LAST, Name "
        "LIMIT 200"
    )

    try:
        res = salesforce_query(instance_url, org_token, soql)
        rows = res.get("records", [])
        
        # Group by journal with document types, first draft sent date, and approval status
        journals_map = {}
        for r in rows:
            j_id = r.get("Journal__c")
            j_name = (r.get("Journal__r") or {}).get("Name")
            j_first_draft = (r.get("Journal__r") or {}).get("First_Draft_Sent__c")
            doc_type = r.get("Document_Type__c")
            doc_status = r.get("Status__c")
            
            if j_id not in journals_map:
                journals_map[j_id] = {
                    "id": j_id, 
                    "name": j_name, 
                    "documentCount": 0,
                    "approvedCount": 0,
                    "firstDraftSent": j_first_draft,
                    "documentTypes": [],
                    "documentStatuses": {}  # Track {docType: approved_count}
                }
            journals_map[j_id]["documentCount"] += 1
            
            # Track approval status
            if doc_status == "Approved":
                journals_map[j_id]["approvedCount"] += 1
            
            # Track document types with approval status
            if doc_type:
                if doc_type not in journals_map[j_id]["documentTypes"]:
                    journals_map[j_id]["documentTypes"].append(doc_type)
                if doc_type not in journals_map[j_id]["documentStatuses"]:
                    journals_map[j_id]["documentStatuses"][doc_type] = {"total": 0, "approved": 0}
                journals_map[j_id]["documentStatuses"][doc_type]["total"] += 1
                if doc_status == "Approved":
                    journals_map[j_id]["documentStatuses"][doc_type]["approved"] += 1
        
        journals = list(journals_map.values())
        
        items = [{
            "id":               r.get("Id"),
            "name":             r.get("Name"),
            "version":          r.get("Version__c"),
            "status":           r.get("Status__c"),
            "s3Key":            r.get("S3_Key__c"),
            "isNewestVersion":  r.get("Is_Newest_Version__c"),
            "documentType":     r.get("Document_Type__c"),
            "marketUnit":       r.get("Market_Unit__c"),
            "sentDate":         r.get("Sent_Date__c"),
            "firstViewed":      r.get("First_Viewed__c"),
            "lastViewed":       r.get("Last_Viewed__c"),
            "journalId":        r.get("Journal__c"),
            "journalName":      (r.get("Journal__r") or {}).get("Name"),
            "sortOrder":        r.get("Sort_Order__c"),
            "isApprovalBlocked": r.get("Is_Approval_Blocked__c"),
        } for r in rows]
        
        return resp(event, 200, {"ok": True, "items": items, "journals": journals})
    except Exception as e:
        log("identifier_list query error:", repr(e))
        return resp(event, 500, {"error": "Salesforce query failed"})

def handle_identifier_doc_url(event, event_json):
    data = event_json or {}
    doc_id = (data.get("docId") or "").strip()
    if not doc_id:
        return resp(event, 400, {"error": "Missing docId"})

    # In dev you may have DEBUG_ALLOW_IDENTIFIER_DOCURL=True to bypass session; otherwise require it.
    token = get_bearer(event)
    if not token and not DEBUG_ALLOW_IDENTIFIER_DOCURL:
        return resp(event, 401, {"error": "Missing session"})

    # If session exists, we will verify the doc belongs to this identifier
    sess = None
    if token:
        try:
            sess = verify_session(token)
        except Exception:
            return resp(event, 401, {"error": "Invalid session"})

    try:
        org_token, instance_url = get_org_token()
    except Exception as e:
        log("identifier_doc_url oauth error:", repr(e))
        return resp(event, 500, {"error": "Salesforce OAuth failed"})

    try:
        safe_id = soql_escape(doc_id)
        if sess and sess.get("typ") == "email":
            soql = (
                "SELECT Id, S3_Key__c, Journal__c, Journal__r.Account__r.PersonEmail, Journal__r.Account__r.Spouse_Email__pc, "
                "       Journal__r.Account__r.Is_Spouse_Shared_Document_Recipient__pc, Status__c "
                "FROM Shared_Document__c "
                "WHERE Id = '" + safe_id + "' "
                "LIMIT 1"
            )
        else:
            soql = (
                "SELECT Id, S3_Key__c, Journal__c, Journal__r.Account__r.Phone_Formatted__c, Journal__r.Account__r.Spouse_Phone__pc, "
                "       Journal__r.Account__r.Is_Spouse_Shared_Document_Recipient__pc, Status__c "
                "FROM Shared_Document__c "
                "WHERE Id = '" + safe_id + "' "
                "LIMIT 1"
            )
        recs = salesforce_query(instance_url, org_token, soql).get("records", [])
        if not recs:
            return resp(event, 404, {"error": "Not found"})
        doc = recs[0]

        # IMPERSONATION: If session is journal-scoped, enforce it
        if sess and sess.get("jid"):
            if doc.get("Journal__c") != sess["jid"]:
                return resp(event, 403, {"error": "Forbidden"})

        # If we have a session, enforce ownership
        if sess:
            account = (doc.get("Journal__r") or {}).get("Account__r", {})
            is_spouse_recipient = account.get("Is_Spouse_Shared_Document_Recipient__pc", False)
            
            if sess.get("typ") == "email":
                email = (sess.get("sub") or "").lower().strip()
                primary_email = (account.get("PersonEmail") or "").lower().strip()
                spouse_email = (account.get("Spouse_Email__pc") or "").lower().strip()
                
                # Allow if primary email OR (spouse recipient enabled AND spouse email)
                if email == primary_email:
                    pass  # OK
                elif is_spouse_recipient and email == spouse_email:
                    pass  # OK
                else:
                    return resp(event, 403, {"error": "Forbidden"})
                    
            elif sess.get("typ") == "phone":
                phone = normalize_phone_basic(sess.get("sub") or "")
                p1 = normalize_phone_basic(account.get("Phone_Formatted__c") or "")
                p2 = account.get("Spouse_Phone__pc") or ""
                
                # Allow if primary phone OR (spouse recipient enabled AND spouse phone)
                if phone == p1:
                    ok = True
                elif is_spouse_recipient and p2:
                    ok = phone in phone_variants_for_match(normalize_phone_basic(p2))
                else:
                    ok = False
                    
                if not ok:
                    return resp(event, 403, {"error": "Forbidden"})

        s3_key = doc.get("S3_Key__c")
        if not s3_key:
            return resp(event, 400, {"error": "Missing S3 key"})

        # Patch Last_Viewed__c and Sent->Viewed (like journal doc-url)
        patch = {"Last_Viewed__c": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")}
        if (doc.get("Status__c") or "").strip().lower() == "sent":
            patch["Status__c"] = "Viewed"
        try:
            salesforce_patch(instance_url, org_token, "Shared_Document__c", doc_id, patch)
        except Exception:
            pass

        url = s3_presign_get(DOCS_BUCKET, s3_key, expires=SESSION_TTL_SECONDS)
        return resp(event, 200, {"ok": True, "url": url})
    except Exception as e:
        log("identifier_doc_url error:", repr(e))
        return resp(event, 500, {"error": "Server error"})

# ===================== DOC LIST / URL (journal) =====================

def handle_doc_list(event, event_json):
    data = event_json or {}
    external_id  = (data.get("externalId")  or "").strip()
    access_token = (data.get("accessToken") or "").strip()
    auth = auth_journal(external_id, access_token)
    if not auth:
        return resp(event, 401, {"error": "Unauthorized"})

    org_token, instance_url = get_org_token()
    soql = (
        "SELECT Id, Name, Version__c, Status__c, S3_Key__c, Is_Newest_Version__c, "
        "Document_Type__c, Market_Unit__c, Sent_Date__c, First_Viewed__c, Last_Viewed__c, Sort_Order__c, "
        "Is_Approval_Blocked__c "
        "FROM Shared_Document__c "
        f"WHERE Journal__c = '{auth['id']}' "
        "ORDER BY Sort_Order__c NULLS LAST, Name"
    )
    rows = salesforce_query(instance_url, org_token, soql).get("records", [])
    items = [{
        "id":               r.get("Id"),
        "name":             r.get("Name"),
        "version":          r.get("Version__c"),
        "status":           r.get("Status__c"),
        "s3Key":            r.get("S3_Key__c"),
        "isNewestVersion":  r.get("Is_Newest_Version__c"),
        "documentType":     r.get("Document_Type__c"),
        "marketUnit":       r.get("Market_Unit__c"),
        "sentDate":         r.get("Sent_Date__c"),
        "firstViewed":      r.get("First_Viewed__c"),
        "lastViewed":       r.get("Last_Viewed__c"),
        "sortOrder":        r.get("Sort_Order__c"),
        "isApprovalBlocked": r.get("Is_Approval_Blocked__c"),
    } for r in rows]
    return resp(event, 200, {"ok": True, "documents": items})

def handle_doc_url(event, event_json):
    data = event_json or {}
    external_id  = (data.get("externalId")  or "").strip()
    access_token = (data.get("accessToken") or "").strip()
    doc_id       = (data.get("docId")       or "").strip()
    if not doc_id:
        return resp(event, 400, {"error": "Missing docId"})
    auth = auth_journal(external_id, access_token)
    if not auth:
        return resp(event, 401, {"error": "Unauthorized"})

    org_token, instance_url = get_org_token()
    safe_id = soql_escape(doc_id)
    soql = (
        "SELECT Id, S3_Key__c, Journal__c, Status__c "
        "FROM Shared_Document__c "
        "WHERE Id = '" + safe_id + "' "
        "LIMIT 1"
    )
    recs = salesforce_query(instance_url, org_token, soql).get("records", [])
    if not recs:
        return resp(event, 404, {"error": "Not found"})
    doc = recs[0]
    if doc.get("Journal__c") != auth["id"]:
        return resp(event, 403, {"error": "Forbidden"})
    s3_key = doc.get("S3_Key__c")
    if not s3_key:
        return resp(event, 400, {"error": "Missing S3 key"})

    patch = {"Last_Viewed__c": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")}
    if (doc.get("Status__c") or "").strip().lower() == "sent":
        patch["Status__c"] = "Viewed"
    try:
        salesforce_patch(instance_url, org_token, "Shared_Document__c", doc_id, patch)
    except Exception:
        pass
    try:
        url = s3_presign_get(DOCS_BUCKET, s3_key, expires=SESSION_TTL_SECONDS)
    except Exception as e:
        log("s3_presign_get error:", repr(e))
        return resp(event, 500, {"error": "S3 presign failed"})
    return resp(event, 200, {"ok": True, "url": url})

# ===================== UPLOAD-START (journal) =====================
_SAFE_CHARS = re.compile(r'[^A-Za-z0-9._-]')

def sanitize_filename(name: str) -> str:
    if not name:
        return "file.pdf"
    base = _SAFE_CHARS.sub('_', name.strip())
    if not base or base in ('.', '..'):
        base = 'file.pdf'
    if len(base) > 180:
        base = base[:180]
    return base

def handle_upload_start(event, event_json):
    data = event_json or {}
    ext_id = (data.get("externalId") or "").strip()
    tok    = (data.get("accessToken") or "").strip()
    files  = data.get("files") or []
    if not ext_id or not tok:
        return resp(event, 400, {"error": "Missing externalId or accessToken"})
    if not isinstance(files, list) or not files:
        return resp(event, 400, {"error": "No files specified"})
    auth = auth_journal(ext_id, tok)
    if not auth:
        return resp(event, 401, {"error": "Unauthorized"})
    org_token, instance_url = get_org_token()

    journal_name = "JOURNAL"
    journal_mu   = None
    try:
        soql = f"SELECT Name, Market_Unit__c FROM Journal__c WHERE Id = '{auth['id']}' LIMIT 1"
        recs = salesforce_query(instance_url, org_token, soql).get("records", [])
    except HTTPError:
        soql = f"SELECT Name FROM Journal__c WHERE Id = '{auth['id']}' LIMIT 1"
        recs = salesforce_query(instance_url, org_token, soql).get("records", [])
    except Exception:
        recs = []
    if not recs:
        return resp(event, 404, {"error": "Journal not found"})

    row = recs[0]
    journal_name  = (row.get("Name") or "JOURNAL").strip()
    journal_lower = journal_name.lower()
    journal_mu    = (row.get("Market_Unit__c") or "").strip() if "Market_Unit__c" in row else None
    base_prefix = s3_base_prefix_for_market(journal_mu)

    items = []
    for f in files:
        raw_name = (f.get("name") or "").strip()
        safe_name = sanitize_filename(raw_name or "file.pdf")
        if not safe_name.lower().endswith(".pdf"):
            safe_name += ".pdf"
        if journal_lower not in safe_name.lower():
            return resp(event, 400, {"error": f'Filename must include the journal number "{journal_name}".'})
        ctype = (f.get("type") or "").strip()
        content_type = ctype or mimetypes.guess_type(safe_name)[0] or "application/pdf"
        s3_key = f"{base_prefix}/{journal_name}/{safe_name}"
        put_url = _s3.generate_presigned_url(
            ClientMethod="put_object",
            Params={"Bucket": DOCS_BUCKET, "Key": s3_key, "ContentType": content_type},
            ExpiresIn=SESSION_TTL_SECONDS
        )
        items.append({"fileName": safe_name, "key": s3_key, "putUrl": put_url, "contentType": content_type})
    return resp(event, 200, {"ok": True, "items": items})

# ===================== APPROVE (journal + identifier) =====================

def handle_doc_approve(event, data):
    ext  = (data.get("externalId")  or "").strip()
    tok  = (data.get("accessToken") or "").strip()
    ids  =  data.get("docIds") or []
    if not ext or not tok or not isinstance(ids, list) or not ids:
        return resp(event, 400, {"error": "Missing externalId, accessToken or docIds"})
    auth = auth_journal(ext, tok)
    if not auth:
        return resp(event, 401, {"error": "Unauthorized"})
    org_tok, inst = get_org_token()
    success, skipped = 0, 0
    for doc_id in ids:
        try:
            q = ("SELECT Id, Journal__c, Is_Approval_Blocked__c FROM Shared_Document__c "
                 f"WHERE Id = '{soql_escape(doc_id)}' LIMIT 1")
            row = salesforce_query(inst, org_tok, q)["records"]
            if not row or row[0].get("Journal__c") != auth["id"]:
                skipped += 1
                continue
            # Check if approval is blocked
            if row[0].get("Is_Approval_Blocked__c") == True:
                skipped += 1
                continue
            salesforce_patch(inst, org_tok, "Shared_Document__c", doc_id, {"Status__c": "Approved"})
            success += 1
        except Exception:
            skipped += 1
    return resp(event, 200, {"ok": True, "approved": success, "skipped": skipped})

def handle_identifier_approve(event, data):
    # Authorization: Bearer <session>
    token = get_bearer(event)
    if not token:
        return resp(event, 401, {"error": "Missing session"})
    try:
        sess = verify_session(token)
    except Exception:
        return resp(event, 401, {"error": "Invalid session"})

    # IMPERSONATION: Check if approval is allowed
    is_impersonation = (sess.get("role") == "impersonation")
    impersonation_can_approve = sess.get("allowApprove", False)
    if is_impersonation and not impersonation_can_approve:
        return resp(event, 403, {"error": "Approval not allowed in impersonation mode"})

    ids = data.get("docIds") or []
    if not isinstance(ids, list) or not ids:
        return resp(event, 400, {"error": "Missing docIds"})

    try:
        org_tok, inst = get_org_token()
        approved, skipped = 0, 0
        for doc_id in ids:
            try:
                safe_id = soql_escape(doc_id)
                if sess.get("typ") == "email":
                    soql = (
                        "SELECT Id, Journal__c, Journal__r.Account__r.PersonEmail, Journal__r.Account__r.Spouse_Email__pc, "
                        "       Journal__r.Account__r.Is_Spouse_Shared_Document_Recipient__pc, "
                        "       Is_Approval_Blocked__c "
                        "FROM Shared_Document__c "
                        "WHERE Id = '" + safe_id + "' LIMIT 1"
                    )
                    recs = salesforce_query(inst, org_tok, soql).get("records", [])
                    if not recs: 
                        skipped += 1; continue
                    row = recs[0]
                    
                    # IMPERSONATION: If session is journal-scoped, enforce it
                    if sess.get("jid"):
                        if row.get("Journal__c") != sess["jid"]:
                            skipped += 1; continue
                    
                    # Check if approval is blocked
                    if row.get("Is_Approval_Blocked__c") == True:
                        skipped += 1; continue
                    
                    acc = (row.get("Journal__r") or {}).get("Account__r", {})
                    email = (sess.get("sub") or "").lower().strip()
                    pe = (acc.get("PersonEmail") or "").lower().strip()
                    se = (acc.get("Spouse_Email__pc") or "").lower().strip()
                    is_spouse_recipient = acc.get("Is_Spouse_Shared_Document_Recipient__pc", False)
                    
                    # Allow if primary email OR (spouse recipient enabled AND spouse email)
                    if email == pe:
                        pass  # OK
                    elif is_spouse_recipient and email == se:
                        pass  # OK
                    else:
                        skipped += 1; continue
                        
                else:
                    soql = (
                        "SELECT Id, Journal__c, Journal__r.Account__r.Phone_Formatted__c, Journal__r.Account__r.Spouse_Phone__pc, "
                        "       Journal__r.Account__r.Is_Spouse_Shared_Document_Recipient__pc, "
                        "       Is_Approval_Blocked__c "
                        "FROM Shared_Document__c "
                        "WHERE Id = '" + safe_id + "' LIMIT 1"
                    )
                    recs = salesforce_query(inst, org_tok, soql).get("records", [])
                    if not recs: 
                        skipped += 1; continue
                    row = recs[0]
                    
                    # IMPERSONATION: If session is journal-scoped, enforce it
                    if sess.get("jid"):
                        if row.get("Journal__c") != sess["jid"]:
                            skipped += 1; continue
                    
                    # Check if approval is blocked
                    if row.get("Is_Approval_Blocked__c") == True:
                        skipped += 1; continue
                    
                    acc = (row.get("Journal__r") or {}).get("Account__r", {})
                    phone = normalize_phone_basic(sess.get("sub") or "")
                    p1    = normalize_phone_basic(acc.get("Phone_Formatted__c") or "")
                    p2raw = acc.get("Spouse_Phone__pc") or ""
                    is_spouse_recipient = acc.get("Is_Spouse_Shared_Document_Recipient__pc", False)
                    
                    # Allow if primary phone OR (spouse recipient enabled AND spouse phone)
                    if phone == p1:
                        ok = True
                    elif is_spouse_recipient and p2raw:
                        ok = phone in phone_variants_for_match(normalize_phone_basic(p2raw))
                    else:
                        ok = False
                        
                    if not ok:
                        skipped += 1; continue

                salesforce_patch(inst, org_tok, "Shared_Document__c", doc_id, {"Status__c": "Approved"})
                approved += 1
            except Exception:
                skipped += 1
        return resp(event, 200, {"ok": True, "approved": approved, "skipped": skipped})
    except Exception as e:
        log("identifier_approve error:", repr(e))
        return resp(event, 500, {"error": "Server error"})

# ===================== AI CHATBOT HELPERS =====================

def extract_pdf_text(bucket: str, key: str) -> dict:
    """
    Extract text from PDF using PyMuPDF (fitz).
    
    Returns:
        {
            'text': str,
            'page_count': int,
            'file_size': int
        }
    """
    try:
        import fitz  # PyMuPDF
        
        log(f"AI: Extracting text from s3://{bucket}/{key}")
        
        # Download PDF from S3
        obj = _s3.get_object(Bucket=bucket, Key=key)
        pdf_bytes = obj['Body'].read()
        file_size = len(pdf_bytes)
        
        log(f"AI: Downloaded {file_size} bytes")
        
        # Open PDF with PyMuPDF
        doc = fitz.open(stream=pdf_bytes, filetype='pdf')
        
        # Extract text from all pages
        text_parts = []
        for page_num in range(len(doc)):
            page = doc[page_num]
            page_text = page.get_text()
            if page_text.strip():
                text_parts.append(f"--- Page {page_num + 1} ---\n{page_text}")
        
        full_text = '\n\n'.join(text_parts)
        page_count = len(doc)
        doc.close()
        
        log(f"AI: Extracted {len(full_text)} characters from {page_count} pages")
        
        return {
            'text': full_text,
            'page_count': page_count,
            'file_size': file_size
        }
        
    except ImportError:
        log("AI ERROR: PyMuPDF (fitz) not available. Check Lambda layer is attached.")
        raise Exception("PyMuPDF not available")
    except Exception as e:
        log(f"AI ERROR: PDF extraction failed: {repr(e)}")
        raise


def get_cached_text(s3_key: str) -> tuple:
    """
    Get cached text from DynamoDB or extract if not cached.
    
    Returns:
        (text: str, was_cached: bool)
    """
    try:
        table = _get_text_cache_table()
        
        # Check cache first
        log(f"AI: Checking cache for {s3_key}")
        response = table.get_item(Key={'s3_key': s3_key})
        
        if 'Item' in response:
            log(f"AI: Cache HIT for {s3_key}")
            return (response['Item']['text'], True)
        
        log(f"AI: Cache MISS for {s3_key}, extracting...")
        
        # Extract PDF text
        result = extract_pdf_text(DOCS_BUCKET, s3_key)
        
        # Cache for 30 days
        from datetime import datetime, timedelta
        ttl = int((datetime.utcnow() + timedelta(days=30)).timestamp())
        
        log(f"AI: Caching text in DynamoDB...")
        table.put_item(Item={
            's3_key': s3_key,
            'text': result['text'],
            'extracted_at': datetime.utcnow().isoformat(),
            'page_count': result['page_count'],
            'file_size': result['file_size'],
            'ttl': ttl
        })
        
        log(f"AI: Text cached successfully (TTL: 30 days)")
        
        return (result['text'], False)
        
    except Exception as e:
        log(f"AI ERROR: get_cached_text failed: {repr(e)}")
        raise


def ask_ai_about_document(document_text: str, question: str, context: dict = None) -> str:
    """
    Send question + document to AWS Bedrock (Claude 3.5 Haiku).
    
    Args:
        document_text: Extracted PDF text
        question: Customer's question
        context: Optional metadata (document name, journal name, brand)
    
    Returns:
        AI-generated answer
    """
    try:
        bedrock = _get_bedrock_client()
        
        log(f"AI: Asking AI (question length: {len(question)} chars)")
        
        # Detect language from brand or question
        brand = (context or {}).get('brand', 'dk').lower()
        lang_map = {'dk': 'Danish', 'se': 'Swedish', 'ie': 'English'}
        default_lang = lang_map.get(brand, 'Danish')
        
        # Build context-aware prompt
        system_prompt = f"""You are a helpful legal document assistant for Din Familiejurist (family law firm).
Your role is to answer customer questions about their legal documents clearly and accurately.

Guidelines:
- Only answer based on the document content provided
- If the answer is not in the document, say so politely
- Use simple, customer-friendly language (avoid legal jargon)
- Be concise but complete
- For dates, amounts, or specific terms, quote the document exactly
- If asked about legal advice, remind them to contact their lawyer
- Respond in the same language as the question (Danish, Swedish, or English)
- Default language: {default_lang}
"""
        
        # Add document context if provided
        context_text = ""
        if context:
            doc_name = context.get('name', 'Unknown')
            journal_name = context.get('journal_name', '')
            context_text = f"\nDocument: {doc_name}\n"
            if journal_name:
                context_text += f"Case: {journal_name}\n"
        
        # Limit document text to ~15K chars (to stay within token limits)
        max_text_length = 15000
        truncated_text = document_text[:max_text_length]
        if len(document_text) > max_text_length:
            truncated_text += f"\n\n[Document truncated - showing first {max_text_length} characters]"
        
        # Build user prompt
        user_prompt = f"""{context_text}
Document content:
{truncated_text}

Customer question: {question}

Please answer the question based on the document content above."""
        
        # Call Bedrock (Claude 3.5 Haiku)
        body = json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 1000,
            "temperature": 0.3,  # Lower = more focused/consistent
            "system": system_prompt,
            "messages": [
                {
                    "role": "user",
                    "content": user_prompt
                }
            ]
        })
        
        start_time = time.time()
        
        response = bedrock.invoke_model(
            modelId=BEDROCK_MODEL_ID,
            body=body
        )
        
        elapsed_time = time.time() - start_time
        
        result = json.loads(response['body'].read())
        answer = result['content'][0]['text']
        
        log(f"AI: Response generated in {elapsed_time:.2f}s ({len(answer)} chars)")
        
        return answer
        
    except Exception as e:
        log(f"AI ERROR: ask_ai_about_document failed: {repr(e)}")
        # Return friendly error message in appropriate language
        brand = (context or {}).get('brand', 'dk').lower()
        if brand == 'se':
            return "Jag beklagar, jag kunde inte behandla din fråga. Försök igen eller kontakta supporten."
        elif brand == 'ie':
            return "I apologize, I couldn't process your question. Please try again or contact support."
        else:
            return "Jeg beklager, jeg kunne ikke behandle dit spørgsmål. Prøv venligst igen eller kontakt support."


# ---------- CHAT (document-scoped) ----------

def handle_chat_send(event, data):
    ext    = (data.get("externalId")  or "").strip()
    tok    = (data.get("accessToken") or "").strip()
    doc_id = (data.get("docId") or "").strip()
    body   = (data.get("body")       or "").strip()
    
    if not body:
        return resp(event, 400, {"error": "Missing body"})
    
    # Determine parent record ID (Journal__c)
    parent_record_id = None
    
    if doc_id:
        # Document-scoped: Get Journal__c from Shared_Document__c
        try:
            org_tok, inst = get_org_token()
            soql = (
                "SELECT Journal__c FROM Shared_Document__c "
                f"WHERE Id = '{soql_escape(doc_id)}' LIMIT 1"
            )
            recs = salesforce_query(inst, org_tok, soql).get("records", [])
            if not recs or not recs[0].get("Journal__c"):
                return resp(event, 400, {"error": "Document not found or missing Journal__c"})
            parent_record_id = recs[0]["Journal__c"]
        except Exception as e:
            log("chat_send doc lookup error:", repr(e))
            return resp(event, 500, {"error": "Salesforce query failed"})
    elif ext and tok:
        # Legacy journal mode: use journal ID directly
        auth = auth_journal(ext, tok)
        if not auth:
            return resp(event, 401, {"error": "Unauthorized"})
        parent_record_id = auth["id"]
    else:
        return resp(event, 400, {"error": "Missing journalId or docId"})
    
    try:
        org_tok, inst = get_org_token()
        rec_id = salesforce_insert(inst, org_tok, "ChatMessage__c", {
            "Parent_Record__c": parent_record_id,
            "Body__c":    body,
            "Is_Inbound__c": True,
        })
        return resp(event, 200, {"ok": True, "id": rec_id})
    except Exception as e:
        log("chat_send error:", repr(e))
        return resp(event, 500, {"error": "Salesforce insert failed"})

def handle_chat_list(event):
    qs = event.get("queryStringParameters") or {}
    ext    = (qs.get("e") or "").strip()
    tok    = (qs.get("t") or "").strip()
    doc_id = (qs.get("docId") or "").strip()
    since  = (qs.get("ince") or qs.get("since") or "").strip()  # keeps backward compat with typo
    
    # Determine parent record ID (Journal__c)
    parent_record_id = None
    
    if doc_id:
        # Document-scoped: Get Journal__c from Shared_Document__c
        try:
            org_tok, inst = get_org_token()
            soql = (
                "SELECT Journal__c FROM Shared_Document__c "
                f"WHERE Id = '{soql_escape(doc_id)}' LIMIT 1"
            )
            recs = salesforce_query(inst, org_tok, soql).get("records", [])
            if not recs or not recs[0].get("Journal__c"):
                return resp(event, 200, {"ok": True, "messages": []})  # Empty list if not found
            parent_record_id = recs[0]["Journal__c"]
        except Exception as e:
            log("chat_list doc lookup error:", repr(e))
            return resp(event, 500, {"error": "Salesforce query failed"})
    elif ext and tok:
        # Legacy journal mode: use journal ID directly
        auth = auth_journal(ext, tok)
        if not auth:
            return resp(event, 401, {"error": "Unauthorized"})
        parent_record_id = auth["id"]
    else:
        return resp(event, 400, {"error": "Missing journalId or docId"})
    
    try:
        org_tok, inst = get_org_token()
        soql = (
            "SELECT Id, Body__c, Is_Inbound__c, CreatedDate, CreatedBy.Name "
            "FROM ChatMessage__c "
            f"WHERE Parent_Record__c = '{soql_escape(parent_record_id)}' " +
            (f"AND CreatedDate > {since} " if since else "") +
            "ORDER BY CreatedDate ASC LIMIT 500"
        )
        rows = salesforce_query(inst, org_tok, soql).get("records", [])
        msgs = [{"id": r["Id"], "body": r.get("Body__c"), "inbound": r.get("Is_Inbound__c", False), "at": r["CreatedDate"]} for r in rows]
        return resp(event, 200, {"ok": True, "messages": msgs})
    except Exception as e:
        log("chat_list error:", repr(e))
        return resp(event, 500, {"error": "Salesforce query failed"})

def handle_identifier_chat_list(event, data):
    # DEBUG: Log what we receive
    log("CHAT_LIST_DEBUG:", {
        "data_keys": list(data.keys()) if data else [],
        "journalId": data.get("journalId") if data else None,
        "raw_body": (event.get("body") or "")[:200]
    })
    
    # Authorization: Bearer <session>
    token = get_bearer(event)
    if not token:
        return resp(event, 401, {"error": "Missing session"})
    try:
        sess = verify_session(token)
    except Exception:
        return resp(event, 401, {"error": "Invalid session"})
    
    # Parse body here if 'data' is empty (fallback)
    if not data:
        log("CHAT_LIST_DEBUG: data is empty, calling _parse_body()")
        data = _parse_body(event)
    
    journal_id = (data.get("journalId") or "").strip()
    if not journal_id:
        log("CHAT_LIST_ERROR: Missing journalId in data. Full data:", data)
        return resp(event, 400, {"error": "Missing journalId"})
    
    since = (data.get("since") or "").strip()
    
    # Query messages for journal
    try:
        org_tok, inst = get_org_token()
        
        # DEBUG: Log the SOQL query
        soql = (
            "SELECT Id, Body__c, Is_Inbound__c, CreatedDate, CreatedBy.Name, "
            "       Message_Type__c, AI_Model__c, AI_Helpful__c, AI_Escalated__c, "
            "       AI_Response_Time__c, Escalated_From__c, "
            "       Original_Target__c, Final_Target__c, Target_Changed__c "
            "FROM ChatMessage__c "
            f"WHERE Parent_Record__c = '{soql_escape(journal_id)}' " +
            (f"AND CreatedDate > {since} " if since else "") +
            "ORDER BY CreatedDate ASC LIMIT 500"
        )
        log("CHAT_LIST_SOQL:", soql)
        
        rows = salesforce_query(inst, org_tok, soql).get("records", [])
        log("CHAT_LIST_RESULTS:", len(rows), "messages")
        
        msgs = [{
            "id": r["Id"],
            "body": r.get("Body__c"),
            "inbound": r.get("Is_Inbound__c", False),
            "at": r["CreatedDate"],
            "messageType": r.get("Message_Type__c"),
            "aiModel": r.get("AI_Model__c"),
            "aiHelpful": r.get("AI_Helpful__c", False),
            "aiEscalated": r.get("AI_Escalated__c", False),
            "aiResponseTime": r.get("AI_Response_Time__c"),
            "escalatedFrom": r.get("Escalated_From__c"),
            "originalTarget": r.get("Original_Target__c"),
            "finalTarget": r.get("Final_Target__c"),
            "targetChanged": r.get("Target_Changed__c", False)
        } for r in rows]
        return resp(event, 200, {"ok": True, "messages": msgs})
    except Exception as e:
        log("identifier_chat_list error:", repr(e))
        log("Full traceback:", traceback.format_exc())
        return resp(event, 500, {"error": "Salesforce query failed"})

def handle_identifier_chat_send(event, data):
    # DEBUG: Log what we receive
    log("CHAT_SEND_DEBUG:", {
        "data_keys": list(data.keys()) if data else [],
        "data_type": type(data).__name__,
        "journalId": data.get("journalId") if data else None,
        "body": data.get("body") if data else None,
        "raw_body": (event.get("body") or "")[:200],
        "is_base64": event.get("isBase64Encoded", False)
    })
    
    # Authorization: Bearer <session>
    token = get_bearer(event)
    if not token:
        return resp(event, 401, {"error": "Missing session"})
    try:
        sess = verify_session(token)
    except Exception:
        return resp(event, 401, {"error": "Invalid session"})
    
    # Parse body here if 'data' is empty (fallback)
    if not data:
        log("CHAT_SEND_DEBUG: data is empty, calling _parse_body()")
        data = _parse_body(event)
        log("CHAT_SEND_DEBUG: After _parse_body:", list(data.keys()) if data else [])
    
    journal_id = (data.get("journalId") or "").strip()
    body       = (data.get("body") or "").strip()
    
    if not journal_id:
        log("CHAT_SEND_ERROR: Missing journalId in data. Full data:", data)
        return resp(event, 400, {"error": "Missing journalId"})
    if not body:
        log("CHAT_SEND_ERROR: Missing body in data. Full data:", data)
        return resp(event, 400, {"error": "Missing body"})
    
    # Insert message directly to journal
    try:
        org_tok, inst = get_org_token()
        
        # Insert inbound message to Human (default chat mode)
        # Original_Target__c = Human (since they're in human chat mode)
        # Message_Type__c is only for OUTBOUND messages
        message_fields = {
            "Parent_Record__c": journal_id,
            "Body__c": body,
            "Is_Inbound__c": True,
            "Original_Target__c": "Human"  # They asked a human
        }
        
        rec_id = salesforce_insert(inst, org_tok, "ChatMessage__c", message_fields)
        log(f"CHAT_SEND_SUCCESS: Created message {rec_id} (Original_Target=Human)")
        return resp(event, 200, {"ok": True, "id": rec_id})
    except Exception as e:
        log("identifier_chat_send error:", repr(e))
        log("Full traceback:", traceback.format_exc())
        return resp(event, 500, {"error": "Salesforce insert failed"})


def handle_identifier_chat_ask(event, data):
    """
    AI-powered document Q&A endpoint.
    
    POST /identifier/chat/ask
    Headers: Authorization: Bearer <session-token>
    Body: {
        "journalId": "a015g00000...",
        "documentId": "a0M5g00000...",
        "question": "What is this document about?",
        "brand": "dk"  // optional, defaults to detected brand
    }
    
    Returns: {
        "answer": "Based on your document...",
        "documentName": "Testament.pdf",
        "isAI": true,
        "cached": true,
        "timestamp": "2025-10-26T..."
    }
    """
    # Check if AI is enabled
    if not AI_ENABLED:
        return resp(event, 503, {"error": "AI chatbot is currently disabled"})
    
    # Authorization: Bearer <session>
    token = get_bearer(event)
    if not token:
        return resp(event, 401, {"error": "Missing session token"})
    
    try:
        sess = verify_session(token)
    except Exception:
        return resp(event, 401, {"error": "Invalid or expired session"})
    
    # Parse request
    journal_id = (data.get("journalId") or "").strip()
    document_id = (data.get("documentId") or "").strip()
    question = (data.get("question") or "").strip()
    brand = (data.get("brand") or detect_brand(event, None) or "dk").strip().lower()
    
    if not all([journal_id, document_id, question]):
        return resp(event, 400, {
            "error": "Missing required fields",
            "required": ["journalId", "documentId", "question"]
        })
    
    try:
        org_tok, inst = get_org_token()
        
        # Get document details from Salesforce
        soql = f"""
            SELECT Id, Name, S3_Key__c, Journal__r.Name
            FROM Shared_Document__c
            WHERE Id = '{soql_escape(document_id)}'
              AND Journal__c = '{soql_escape(journal_id)}'
            LIMIT 1
        """
        
        result = salesforce_query(inst, org_tok, soql)
        if not result.get('records'):
            log(f"AI ERROR: Document not found - docId={document_id}, journalId={journal_id}")
            return resp(event, 404, {"error": "Document not found or access denied"})
        
        doc = result['records'][0]
        s3_key = doc.get('S3_Key__c')
        
        if not s3_key:
            log(f"AI ERROR: Document has no S3 key - docId={document_id}")
            return resp(event, 400, {"error": "Document has no S3 key"})
        
        log(f"AI: Processing question for document: {s3_key}")
        
        # 1. CREATE customer's question (inbound ChatMessage) with routing metadata
        #    Original_Target__c = AI (since they asked AI)
        #    Final_Target__c and Target_Changed__c will be set later if user changes routing
        inbound_fields = {
            "Parent_Record__c": journal_id,
            "Body__c": question,
            "Is_Inbound__c": True,
            "Original_Target__c": "AI"  # They asked the AI
        }
        
        # Note: Message_Type__c is only for OUTBOUND messages
        # Final_Target__c and Target_Changed__c are initially null/false
        
        inbound_id = salesforce_insert(inst, org_tok, "ChatMessage__c", inbound_fields)
        log(f"AI: Created inbound ChatMessage: {inbound_id} (Original_Target=AI)")
        
        # Get or extract document text
        start_time = time.time()
        document_text, was_cached = get_cached_text(s3_key)
        
        if not document_text:
            log(f"AI ERROR: Could not extract text from {s3_key}")
            return resp(event, 500, {"error": "Could not extract document text"})
        
        # Prepare context for AI
        context = {
            'name': doc.get('Name', 'Unknown'),
            'journal_name': doc.get('Journal__r', {}).get('Name', ''),
            'brand': brand
        }
        
        # Ask AI
        answer = ask_ai_about_document(document_text, question, context)
        elapsed_ms = int((time.time() - start_time) * 1000)
        
        # 2. CREATE AI's response (outbound ChatMessage)
        outbound_id = salesforce_insert(inst, org_tok, "ChatMessage__c", {
            "Parent_Record__c": journal_id,
            "Body__c": answer,
            "Is_Inbound__c": False,
            "Message_Type__c": "AI",
            "AI_Model__c": BEDROCK_MODEL_ID,
            "AI_Response_Time__c": elapsed_ms
        })
        log(f"AI: Created outbound ChatMessage: {outbound_id} (response time: {elapsed_ms}ms)")
        
        # Log interaction (for monitoring and quality improvement)
        log(f"AI: Answered question - docId={document_id}, questionLen={len(question)}, answerLen={len(answer)}, cached={was_cached}")
        
        return resp(event, 200, {
            "answer": answer,
            "documentName": context['name'],
            "isAI": True,
            "cached": was_cached,
            "timestamp": datetime.datetime.utcnow().isoformat(),
            "inboundMessageId": inbound_id,
            "outboundMessageId": outbound_id,
            "responseTimeMs": elapsed_ms
        })
        
    except Exception as e:
        log(f"AI ERROR: chat/ask failed: {repr(e)}")
        log("Full traceback:", traceback.format_exc())
        return resp(event, 500, {
            "error": "AI query failed",
            "details": str(e) if os.environ.get("DEBUG") else "Internal server error"
        })


def handle_identifier_chat_feedback(event, data):
    """
    Handle AI message feedback (helpful or escalate to human).
    
    POST /identifier/chat/feedback
    Headers: Authorization: Bearer <session-token>
    Body: {
        "messageId": "a0V5g000002",  // ID of the OUTBOUND AI message
        "action": "helpful" | "escalate"
    }
    
    Returns: {
        "ok": true
    }
    """
    # Authorization: Bearer <session>
    token = get_bearer(event)
    if not token:
        return resp(event, 401, {"error": "Missing session token"})
    
    try:
        sess = verify_session(token)
    except Exception:
        return resp(event, 401, {"error": "Invalid or expired session"})
    
    # Parse request
    message_id = (data.get("messageId") or "").strip()
    action = (data.get("action") or "").strip().lower()
    
    if not message_id:
        return resp(event, 400, {"error": "Missing messageId"})
    
    if action not in ("helpful", "escalate"):
        return resp(event, 400, {"error": "Invalid action. Must be 'helpful' or 'escalate'"})
    
    try:
        org_tok, inst = get_org_token()
        
        if action == "helpful":
            # Mark the AI OUTBOUND message as helpful
            salesforce_patch(inst, org_tok, "ChatMessage__c", message_id, {
                "AI_Helpful__c": True
            })
            log(f"AI Feedback: Outbound message {message_id} marked as helpful")
            return resp(event, 200, {"ok": True})
        
        elif action == "escalate":
            # 1. Get the AI OUTBOUND message to find the journal and timestamp
            ai_msg_soql = f"""
                SELECT Id, Parent_Record__c, CreatedDate
                FROM ChatMessage__c
                WHERE Id = '{soql_escape(message_id)}'
                  AND Is_Inbound__c = false
                  AND Message_Type__c = 'AI'
                LIMIT 1
            """
            ai_msg_result = salesforce_query(inst, org_tok, ai_msg_soql)
            if not ai_msg_result.get('records'):
                return resp(event, 404, {"error": "AI outbound message not found"})
            
            ai_msg = ai_msg_result['records'][0]
            journal_id = ai_msg.get('Parent_Record__c')
            ai_created = ai_msg.get('CreatedDate')
            
            # 2. Find the original customer question (most recent INBOUND message before this AI outbound message)
            #    This is the message we need to UPDATE (not create a new one)
            original_soql = f"""
                SELECT Id, Body__c, Original_Target__c
                FROM ChatMessage__c
                WHERE Parent_Record__c = '{soql_escape(journal_id)}'
                  AND Is_Inbound__c = true
                  AND CreatedDate < {ai_created}
                ORDER BY CreatedDate DESC
                LIMIT 1
            """
            original_result = salesforce_query(inst, org_tok, original_soql)
            
            if not original_result.get('records'):
                log(f"AI Escalate: Could not find original question for AI message {message_id}")
                return resp(event, 400, {"error": "Could not find original question"})
            
            original = original_result['records'][0]
            original_id = original.get('Id')
            original_target = original.get('Original_Target__c', 'AI')
            
            # 3. UPDATE the original INBOUND message to show it was escalated to Human
            salesforce_patch(inst, org_tok, "ChatMessage__c", original_id, {
                "Final_Target__c": "Human",
                "Target_Changed__c": True,
                "Escalated_From__c": message_id  # Link to the AI response they're escalating from
            })
            log(f"AI Escalate: Updated inbound message {original_id} (Original: {original_target} -> Final: Human)")
            
            # 4. Mark the AI OUTBOUND message as escalated (for reference)
            salesforce_patch(inst, org_tok, "ChatMessage__c", message_id, {
                "AI_Escalated__c": True
            })
            log(f"AI Escalate: Marked outbound AI message {message_id} as escalated")
            
            return resp(event, 200, {"ok": True})
        
    except Exception as e:
        log(f"AI Feedback ERROR: {repr(e)}")
        log("Full traceback:", traceback.format_exc())
        return resp(event, 500, {"error": "Feedback processing failed"})


def handle_identifier_chat_switch_to_ai(event, data):
    """
    Handle switching a Human-targeted question to AI.
    When user clicks "Ask AI" button on a message originally sent to Human.
    
    POST /identifier/chat/switch-to-ai
    Headers: Authorization: Bearer <session-token>
    Body: {
        "messageId": "a0V5g000002",  // ID of the INBOUND Human message
        "journalId": "a015g00000...",
        "documentId": "a0M5g00000...",
        "brand": "dk"  // optional
    }
    
    Returns: {
        "ok": true,
        "answer": "AI response...",
        "outboundMessageId": "a0V5g000003"
    }
    """
    # Authorization: Bearer <session>
    token = get_bearer(event)
    if not token:
        return resp(event, 401, {"error": "Missing session token"})
    
    try:
        sess = verify_session(token)
    except Exception:
        return resp(event, 401, {"error": "Invalid or expired session"})
    
    # Parse request
    message_id = (data.get("messageId") or "").strip()
    journal_id = (data.get("journalId") or "").strip()
    document_id = (data.get("documentId") or "").strip()
    brand = (data.get("brand") or detect_brand(event, None) or "dk").strip().lower()
    
    if not all([message_id, journal_id, document_id]):
        return resp(event, 400, {
            "error": "Missing required fields",
            "required": ["messageId", "journalId", "documentId"]
        })
    
    try:
        org_tok, inst = get_org_token()
        
        # 1. Get the original INBOUND message
        msg_soql = f"""
            SELECT Id, Body__c, Original_Target__c, Final_Target__c, Target_Changed__c
            FROM ChatMessage__c
            WHERE Id = '{soql_escape(message_id)}'
              AND Is_Inbound__c = true
              AND Parent_Record__c = '{soql_escape(journal_id)}'
            LIMIT 1
        """
        msg_result = salesforce_query(inst, org_tok, msg_soql)
        if not msg_result.get('records'):
            return resp(event, 404, {"error": "Message not found"})
        
        msg = msg_result['records'][0]
        question = msg.get('Body__c', '')
        original_target = msg.get('Original_Target__c', 'Human')
        
        # 2. UPDATE the message to show it was switched to AI
        salesforce_patch(inst, org_tok, "ChatMessage__c", message_id, {
            "Final_Target__c": "AI",
            "Target_Changed__c": True
        })
        log(f"Switch to AI: Updated message {message_id} (Original: {original_target} -> Final: AI)")
        
        # 3. Get document for AI processing
        doc_soql = f"""
            SELECT Id, Name, S3_Key__c, Journal__r.Name
            FROM Shared_Document__c
            WHERE Id = '{soql_escape(document_id)}'
              AND Journal__c = '{soql_escape(journal_id)}'
            LIMIT 1
        """
        doc_result = salesforce_query(inst, org_tok, doc_soql)
        if not doc_result.get('records'):
            return resp(event, 404, {"error": "Document not found"})
        
        doc = doc_result['records'][0]
        s3_key = doc.get('S3_Key__c')
        
        if not s3_key:
            return resp(event, 400, {"error": "Document has no S3 key"})
        
        log(f"Switch to AI: Processing question for document: {s3_key}")
        
        # 4. Get document text and ask AI
        start_time = time.time()
        document_text, was_cached = get_cached_text(s3_key)
        
        if not document_text:
            log(f"Switch to AI ERROR: Could not extract text from {s3_key}")
            return resp(event, 500, {"error": "Could not extract document text"})
        
        context = {
            'name': doc.get('Name', 'Unknown'),
            'journal_name': doc.get('Journal__r', {}).get('Name', ''),
            'brand': brand
        }
        
        answer = ask_ai_about_document(document_text, question, context)
        elapsed_ms = int((time.time() - start_time) * 1000)
        
        # 5. CREATE AI's response (outbound ChatMessage)
        outbound_id = salesforce_insert(inst, org_tok, "ChatMessage__c", {
            "Parent_Record__c": journal_id,
            "Body__c": answer,
            "Is_Inbound__c": False,
            "Message_Type__c": "AI",
            "AI_Model__c": BEDROCK_MODEL_ID,
            "AI_Response_Time__c": elapsed_ms
        })
        log(f"Switch to AI: Created outbound AI message {outbound_id}")
        
        return resp(event, 200, {
            "ok": True,
            "answer": answer,
            "outboundMessageId": outbound_id,
            "responseTimeMs": elapsed_ms
        })
        
    except Exception as e:
        log(f"Switch to AI ERROR: {repr(e)}")
        log("Full traceback:", traceback.format_exc())
        return resp(event, 500, {"error": "Switch to AI failed"})


# ===================== HEALTH =====================

def handle_ping(event):
    # Keep payload tiny to simplify curl | json.tool
    return resp(event, 200, {"ok": True})

def handle_sf_oauth_check(event):
    try:
        tok, inst = get_org_token()
        return resp(event, 200, {"ok": True, "instanceUrl": inst})
    except HTTPError as e:
        try:
            body = e.read().decode("utf-8", "ignore")
        except Exception:
            body = ""
        return resp(event, 502, {"ok": False, "httpStatus": getattr(e, "code", None), "body": body})
    except Exception as e:
        return resp(event, 502, {"ok": False, "error": repr(e)})

# ===================== ROUTER =====================

# NEW: robust body parsing for API Gateway HTTP APIs (json + base64 + form-url-encoded)
def _parse_body(event):
    raw = event.get("body") or ""
    if not raw:
        return {}
    try:
        if event.get("isBase64Encoded"):
            raw = base64.b64decode(raw).decode("utf-8", "ignore")
    except Exception:
        pass
    # Try JSON
    try:
        return json.loads(raw or "{}") or {}
    except Exception:
        # Try x-www-form-urlencoded
        try:
            parsed = urllib.parse.parse_qs(raw, keep_blank_values=True)
            return {k: (v[0] if isinstance(v, list) else v) for k, v in parsed.items()}
        except Exception:
            return {}

def lambda_handler(event, context):
    try:
        method = (event.get("requestContext", {}).get("http", {}).get("method") or "").upper()
        path   = (event.get("rawPath") or "").lower()

        if method == "OPTIONS":
            # Simple CORS response
            return resp(event, 200, {"ok": True})

        data = {}
        if method in ("POST", "PUT", "PATCH"):
            data = _parse_body(event)

        # Health / diagnostics
        if path.endswith("/ping")                       and method == "GET":  return handle_ping(event)
        if path.endswith("/diag/net")                   and method == "GET":  return handle_diag_net(event)
        if path.endswith("/sf-oauth-check")             and method == "GET":  return handle_sf_oauth_check(event)

        # Client Impersonation (NEW)
        if path.endswith("/impersonation/login")        and method == "POST": return handle_impersonation_login(event, data)

        # Identifier OTP/session (new)
        if path.endswith("/identifier/request-otp")     and method == "POST": return handle_identifier_request_otp(event, data)
        if path.endswith("/identifier/verify-otp")      and method == "POST": return handle_identifier_verify_otp(event, data)
        if path.endswith("/identifier/list")            and method == "POST": return handle_identifier_list(event, data)
        if path.endswith("/identifier/doc-url")         and method == "POST": return handle_identifier_doc_url(event, data)
        if path.endswith("/identifier/approve")         and method == "POST": return handle_identifier_approve(event, data)
        if path.endswith("/identifier/search")          and method == "POST": return handle_identifier_search(event, data)  # NEW: uses robust body parsing

        # Legacy journal flow
        if path.endswith("/otp/init")                   and method == "POST": return handle_otp_init(event, data)
        if path.endswith("/otp-send")                   and method == "POST": return handle_otp_send(event, data)
        if path.endswith("/otp-verify")                 and method == "POST": return handle_otp_verify(event, data)
        if path.endswith("/doc-list")                   and method == "POST": return handle_doc_list(event, data)
        if path.endswith("/doc-url")                    and method == "POST": return handle_doc_url(event, data)
        if path.endswith("/upload-start")               and method == "POST": return handle_upload_start(event, data)
        if path.endswith("/approve")                    and method == "POST": return handle_doc_approve(event, data)

        # Chat (identifier-specific routes MUST come before journal routes to avoid path collision!)
        if path.endswith("/identifier/chat/ask")        and method == "POST": return handle_identifier_chat_ask(event, data)
        if path.endswith("/identifier/chat/feedback")   and method == "POST": return handle_identifier_chat_feedback(event, data)
        if path.endswith("/identifier/chat/switch-to-ai") and method == "POST": return handle_identifier_chat_switch_to_ai(event, data)
        if path.endswith("/identifier/chat/send")       and method == "POST": return handle_identifier_chat_send(event, data)
        if path.endswith("/identifier/chat/list")       and method == "POST": return handle_identifier_chat_list(event, data)
        
        # Chat (journal legacy)
        if path.endswith("/chat/send")                  and method == "POST": return handle_chat_send(event, data)
        if path.endswith("/chat/list")                  and method == "GET":  return handle_chat_list(event)

        return resp(event, 404, {"error": "Not Found"})

    except HTTPError as e:
        try:
            log("Top-level HTTPError:", e.code, e.reason)
            log("HTTPError body:", e.read().decode("utf-8"))
        except Exception:
            log("Top-level HTTPError (no body readable)")
        return resp(event, 500, {"error": "Server error"})
    except Exception as e:
        log("Top-level exception:", repr(e))
        log(traceback.format_exc())
        return resp(event, 500, {"error": "Server error"})

# ===================== COMPAT HELPERS (unchanged) =====================

def handle_otp_init(event, _):   # kept for compatibility
    return resp(event, 200, {"ok": True})

def handle_identifier_search(event, event_json):
    # (unchanged) count-only helper—safe to keep; now benefits from _parse_body robustness
    data = event_json or {}
    raw_email = (data.get("email") or "").strip()
    raw_phone = (data.get("phone") or "").strip()
    has_email = bool(raw_email); has_phone = bool(raw_phone)
    if not (has_email ^ has_phone):
        return resp(event, 400, {"error": "Provide exactly one of: email OR phone"})
    try:
        org_token, instance_url = get_org_token()
        if has_email:
            email = raw_email.lower()
            if "@" not in email or "." not in email.split("@")[-1]:
                return resp(event, 400, {"error": "Invalid email format"})
            esc = email.replace("'", "\\'")
            soql = (
                "SELECT COUNT() FROM Shared_Document__c WHERE "
                "(Journal__r.Account__r.PersonEmail = '" + esc + "' "
                "OR (Journal__r.Account__r.Is_Spouse_Shared_Document_Recipient__pc = true "
                "AND Journal__r.Account__r.Spouse_Email__pc = '" + esc + "'))"
            )
            count = salesforce_query(instance_url, org_token, soql).get("totalSize", 0)
            return resp(event, 200, {"ok": True, "identifierType": "email", "identifier": email, "matchCount": count})
        else:
            phone = normalize_phone_basic(raw_phone)
            if not any(ch.isdigit() for ch in phone):
                return resp(event, 400, {"error": "Invalid phone format"})
            esc_vals = ["'" + v.replace("'", "\\'") + "'" for v in phone_variants_for_match(phone)]
            in_clause = ", ".join(esc_vals) if esc_vals else "''"
            soql = (
                "SELECT COUNT() FROM Shared_Document__c WHERE "
                "(Journal__r.Account__r.Phone_Formatted__c = '" + phone.replace("'", "\\'") + "' "
                "OR (Journal__r.Account__r.Is_Spouse_Shared_Document_Recipient__pc = true "
                "AND Journal__r.Account__r.Spouse_Phone__pc IN (" + in_clause + ")))"
            )
            count = salesforce_query(instance_url, org_token, soql).get("totalSize", 0)
            return resp(event, 200, {"ok": True, "identifierType": "phone", "identifier": phone, "matchCount": count})
    except Exception as e:
        log("identifier_search error:", repr(e))
        return resp(event, 500, {"error": "Salesforce query failed"})
