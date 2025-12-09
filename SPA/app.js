/* ------------------------------------------------------------------
   Redirect old journal links to identifier mode
------------------------------------------------------------------ */
(function redirectOldLinks(){
  const qs = new URLSearchParams(location.search);
  const hasE = qs.has('e');
  const hasT = qs.has('t');
  
  // If old journal parameters exist, redirect to clean URL
  if (hasE || hasT) {
    const cleanUrl = location.origin + location.pathname;
    window.location.replace(cleanUrl);
    return; // Stop execution
  }
})();

/* ------------------------------------------------------------------
   Konfiguration & helpers
------------------------------------------------------------------ */
const API  = new URLSearchParams(location.search).get('api')
          || 'https://ysu7eo2haj.execute-api.eu-north-1.amazonaws.com/prod';

// Journal endpoints (unchanged)
const OTP_VERIFY = `${API}/otp-verify`,
      OTP_SEND   = `${API}/otp-send`,
      DOC_LIST   = `${API}/doc-list`,
      DOC_URL    = `${API}/doc-url`,
      APPROVE_URL= `${API}/approve`,
      CHAT_LIST  = `${API}/chat/list`,
      CHAT_SEND  = `${API}/chat/send`;

// Identifier endpoints
const ID_REQUEST_OTP = `${API}/identifier/request-otp`,
      ID_VERIFY_OTP  = `${API}/identifier/verify-otp`,
      ID_LIST        = `${API}/identifier/list`,
      ID_DOC_URL     = `${API}/identifier/doc-url`,
      ID_APPROVE     = `${API}/identifier/approve`,
      IMPERSONATION_LOGIN = `${API}/impersonation/login`;

/* Impersonation state */
let impersonationMode = false;
let impersonationAllowApprove = false;

/* Default intro video */
const DEFAULT_VIDEO_URL = 'https://www.youtube.com/embed/UsFmArdrO8s?rel=0';
function ytUrlWithSafeParams(url){
  try{
    const u = new URL(url);
    let id = '';
    if (u.hostname === 'youtu.be') id = u.pathname.slice(1);
    else if (u.pathname.startsWith('/embed/')) id = u.pathname.split('/embed/')[1];
    else id = u.searchParams.get('v') || '';
    if (id){
      u.searchParams.set('rel','0');
      u.searchParams.set('modestbranding','1');
      u.searchParams.set('playsinline','1');
      u.searchParams.set('autoplay','0');
      u.searchParams.set('loop','0');
      u.searchParams.delete('playlist');
    }
    return u.toString();
  }catch(_){ return url; }
}

const qs          = new URLSearchParams(location.search),
      externalId  = qs.get('e') || '',
      accessToken = qs.get('t') || '';

const MODE = (externalId && accessToken) ? 'journal' : 'identifier';

/* ---------------- Identifier session state ---------------- */
let identifierType  = 'phone';    // 'phone' | 'email'
let identifierValue = '';         // e164 phone or email string for verify-sub
let sessionToken    = '';         // Bearer token returned by /identifier/verify-otp
let availableJournals = [];       // journals found for identifier (for selection)
let selectedJournalId = '';       // currently selected journal ID
let selectedJournalName = '';     // currently selected journal name (e.g. "J-0055362")

/* Brand-aware options */
const VIDEO_URL  = qs.get('video') || (window.__BRAND && window.__BRAND.video) || DEFAULT_VIDEO_URL;
const SHOW_INTRO = (window.__BRAND && window.__BRAND.showVideo) !== false;
const SHOW_FAQ = (window.__BRAND && typeof window.__BRAND.showFAQ !== 'undefined')
  ? !!window.__BRAND.showFAQ
  : true;
const BRAND_KEY = (document.documentElement.getAttribute('data-brand') || 'dk').toLowerCase();
const DEFAULT_PHONE_ISO = (window.__BRAND && window.__BRAND.countryIso) || (BRAND_KEY==='se' ? 'SE' : BRAND_KEY==='ie' ? 'IE' : 'DK');

const $    = id => document.getElementById(id),
      show = el => el && el.classList.remove('hidden'),
      hide = el => el && el.classList.add('hidden'),
      setMsg = t => { const m=$('msg'); if(m) m.textContent = t || ''; },
      setIdMsg = t => { const m=$('idMsg'); if(m) m.textContent = t || ''; },
      spin   = on => { const ov=$('loadingOverlay'); if(ov) ov.classList.toggle('hidden', !on); };

const SHOW_APPROVE_ALL = false;

const CHAT_SEEN_KEY = 'dfj_chat_opened';
function hasSeenLabel(){
  try { return localStorage.getItem(CHAT_SEEN_KEY) === '1'; } catch(e){ return false; }
}

let docs = [], active = 0, completionShown = false, currentPresigned = '';
let shouldStartTour = false, tourActive = false;

/* Session expiration handler */
function handleSessionExpired(){
  console.log('handleSessionExpired: Session expired or invalid, resetting to OTP screen');
  
  // Clear session state
  sessionToken = '';
  
  // Clear impersonation state
  impersonationMode = false;
  impersonationAllowApprove = false;
  
  // Hide impersonation banner if present
  const banner = document.querySelector('.impersonation-banner');
  if (banner) banner.remove();
  
  // Clear UI state
  docs = [];
  active = 0;
  completionShown = false;
  currentPresigned = '';
  
  // Clear any active session refresh timer
  if (window.sessionRefreshTimer) {
    clearTimeout(window.sessionRefreshTimer);
    window.sessionRefreshTimer = null;
  }
  
  // Reset to OTP screen
  hide($('sidebar'));
  hide($('viewerCard'));
  hide($('chatFab'));
  hide($('chatLabel'));
  show($('otpCard'));
  
  // Show appropriate step based on mode
  if (MODE === 'identifier') {
    // Back to identifier entry
    showStep('id');
    setIdMsg(_t_safe('SESSION_EXPIRED') || 'Session expired. Please sign in again.');
  } else {
    // Back to OTP verification for journal mode
    showStep('verify');
    setVerifySub();
    setMsg(_t_safe('SESSION_EXPIRED') || 'Session expired. Please enter the code again.');
  }
  
  spin(false);
}

/* ----------------------------------------------------------
   Session validation and proactive refresh helpers
---------------------------------------------------------- */
/**
 * Checks if the current session token is still valid
 * Returns true if valid, false if expired or invalid
 * NOTE: If token is not JWT format, returns true (assumes valid)
 * This is because the backend will return 401 if actually expired
 */
function isSessionValid() {
  if (!sessionToken) {
    console.warn('isSessionValid: No session token present');
    return false;
  }
  
  try {
    // Parse JWT-style token (format: header.payload.signature)
    const parts = sessionToken.split('.');
    if (parts.length !== 3) {
      // Token is not JWT format - assume it's a simple token string
      // The backend will validate it and return 401 if expired
      console.log('isSessionValid: Token is not JWT format, assuming valid (backend will validate)');
      return true;
    }
    
    // Decode payload (base64url)
    const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
    
    // Check exp claim
    if (!payload.exp) {
      console.warn('isSessionValid: No exp claim in token, assuming valid');
      return true;
    }
    
    const now = Math.floor(Date.now() / 1000);
    const bufferSeconds = 300; // 5-minute buffer
    const isValid = payload.exp > (now + bufferSeconds);
    
    if (!isValid) {
      console.warn(`isSessionValid: Token expires at ${payload.exp}, current time ${now} (with ${bufferSeconds}s buffer)`);
    }
    
    return isValid;
  } catch (err) {
    console.error('isSessionValid: Error parsing token, assuming valid:', err);
    // If we can't parse it, assume it's valid and let the backend reject it if needed
    return true;
  }
}

/**
 * Starts a timer to proactively refresh the session before it expires
 * Should be called after successful OTP verification or impersonation login
 * NOTE: Only works if token is JWT format with exp claim
 */
function startSessionRefreshTimer() {
  // Clear any existing timer
  if (window.sessionRefreshTimer) {
    clearTimeout(window.sessionRefreshTimer);
    window.sessionRefreshTimer = null;
  }
  
  if (!sessionToken) {
    console.warn('startSessionRefreshTimer: No session token to refresh');
    return;
  }
  
  try {
    // Parse token to get expiry
    const parts = sessionToken.split('.');
    if (parts.length !== 3) {
      console.log('startSessionRefreshTimer: Token is not JWT format, skipping automatic refresh');
      return;
    }
    
    const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
    if (!payload.exp) {
      console.log('startSessionRefreshTimer: No exp claim in token, skipping automatic refresh');
      return;
    }
    
    const now = Math.floor(Date.now() / 1000);
    const expiresIn = payload.exp - now;
    
    // Refresh 2 minutes before expiry (120 seconds)
    const refreshIn = Math.max(0, expiresIn - 120);
    
    console.log(`startSessionRefreshTimer: Session expires in ${expiresIn}s, will refresh in ${refreshIn}s`);
    
    window.sessionRefreshTimer = setTimeout(async () => {
      console.log('Session refresh timer triggered, fetching docs to get new token...');
      try {
        await fetchDocs();
        console.log('Session refreshed successfully');
        // Restart the timer for the new token
        startSessionRefreshTimer();
      } catch (err) {
        console.error('Failed to refresh session:', err);
        // If refresh fails, user will hit session expiry on next API call
      }
    }, refreshIn * 1000);
  } catch (err) {
    console.error('startSessionRefreshTimer: Error setting up timer:', err);
  }
}

/**
 * Global API wrapper that handles 401 session expiration responses
 * Use this instead of raw fetch() for all API calls
 */
async function apiCall(url, options = {}) {
  try {
    const res = await fetch(url, options);
    
    // Check for session expiration
    if (res.status === 401) {
      console.warn('apiCall: Received 401 Unauthorized, session expired');
      handleSessionExpired();
      throw new Error('Session expired');
    }
    
    return res;
  } catch (err) {
    // Re-throw fetch errors (network issues, etc.)
    throw err;
  }
}

/* ----------------------------------------------------------
   Impersonation mode detection and auto-boot
---------------------------------------------------------- */
async function bootImpersonationIfPresent() {
  const params = new URLSearchParams(location.search);
  const token = params.get('impersonate');
  
  if (!token) return false; // Not an impersonation link
  
  // Show loading
  spin(true);
  
  try {
    const res = await fetch(IMPERSONATION_LOGIN, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token })
    });
    
    const json = await res.json();
    
    // Check if token was already used or other error
    if (!res.ok || !json.ok) {
      const errorMsg = json.error || 'Impersonation login failed';
      
      // Show a nice error page for already-used tokens or other errors
      showImpersonationError(errorMsg);
      spin(false);
      return false;
    }
    
    // Store session and metadata
    sessionToken = json.session;
    impersonationMode = true;
    impersonationAllowApprove = json.allowApprove || false;
    
    // Start proactive session refresh timer
    startSessionRefreshTimer();
    
    // Select the journal
    selectedJournalId = json.journalId;
    selectedJournalName = json.journalName || selectedJournalId;
    
    // Clean URL (remove token from address bar for security)
    const cleanUrl = location.origin + location.pathname;
    window.history.replaceState({}, '', cleanUrl);
    
    // Show impersonation banner
    showImpersonationBanner();
    
    // Load documents for the journal
    await fetchDocs();
    
    // Enter portal UI (hide OTP, show sidebar and viewer)
    enterPortalUI();
    
    // Render sidebar and display first document
    renderLists();
    if (docs.length > 0) {
      active = 0;
      await loadCurrent();
    }
    
    return true;
  } catch (err) {
    showImpersonationError(err.message || 'Failed to load impersonation session');
    spin(false);
    return false;
  }
}

function showImpersonationError(errorMessage) {
  // Hide all other UI
  hide($('sidebar'));
  hide($('viewerCard'));
  hide($('chatFab'));
  hide($('chatLabel'));
  
  // Show OTP card with error message
  const otpCard = $('otpCard');
  if (!otpCard) return;
  
  otpCard.innerHTML = `
    <div style="padding: 40px; max-width: 500px; margin: 0 auto; text-align: center;">
      <svg style="width: 80px; height: 80px; color: #e74c3c; margin-bottom: 24px;" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <circle cx="12" cy="12" r="10"></circle>
        <line x1="12" y1="8" x2="12" y2="12"></line>
        <line x1="12" y1="16" x2="12.01" y2="16"></line>
      </svg>
      
      <h2 style="font-size: 24px; font-weight: 600; margin-bottom: 12px; color: #2c3e50;">
        ${_t_safe('IMPERSONATION_ERROR_TITLE') || 'Access Link Error'}
      </h2>
      
      <p style="font-size: 16px; color: #7f8c8d; margin-bottom: 24px; line-height: 1.6;">
        ${errorMessage}
      </p>
      
      <div style="padding: 16px; background: #fff3cd; border: 1px solid #ffc107; border-radius: 8px; margin-top: 24px;">
        <p style="font-size: 14px; color: #856404; margin: 0;">
          ${_t_safe('IMPERSONATION_ERROR_HINT') || 'If you need access to these documents, please contact your legal advisor to generate a new link.'}
        </p>
      </div>
    </div>
  `;
  
  show(otpCard);
}

function showImpersonationBanner() {
  // Check if banner already exists
  if (document.querySelector('.impersonation-banner')) return;
  
  const banner = document.createElement('div');
  banner.className = 'impersonation-banner';
  banner.innerHTML = `
    <svg class="impersonation-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
      <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"></path>
      <circle cx="9" cy="7" r="4"></circle>
      <path d="M23 21v-2a4 4 0 0 0-3-3.87"></path>
      <path d="M16 3.13a4 4 0 0 1 0 7.75"></path>
    </svg>
    <span class="impersonation-text">
      ${_t_safe('IMPERSONATION_MODE') || 'Viewing as client'} • ${selectedJournalName}
      ${impersonationAllowApprove ? '' : ' • ' + (_t_safe('READ_ONLY') || 'Read-only')}
    </span>
  `;
  document.body.appendChild(banner);
}

function isSessionExpired(response, json){
  // Check for 401 status or session-related errors
  if (response.status === 401) return true;
  if (json && typeof json.error === 'string'){
    const err = json.error.toLowerCase();
    if (err.includes('session') || err.includes('expired') || err.includes('unauthorized') || err.includes('invalid token')) return true;
  }
  return false;
}

/* ----------------------------------------------------------
   Focus helpers (exclusive + visibility-aware)
   - Ensures only the latest requested focus "wins"
   - Waits until element is visible (not in a .hidden container)
   - Uses rAF + small retries for iOS Safari after class toggles
---------------------------------------------------------- */
const focusManager = (() => {
  let token = 0;
  let timer = null;

  function isVisible(el){
    if (!el || el.disabled) return false;
    // Hidden via CSS display:none or visibility:hidden
    const cs = window.getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden') return false;
    // Hidden via ancestor .hidden (display:none !important)
    let p = el;
    while (p) {
      if (p.classList && p.classList.contains('hidden')) return false;
      p = p.parentElement;
    }
    // If inside a display:none parent, offsetParent will be null (except position:fixed)
    if (!el.offsetParent && cs.position !== 'fixed') return false;
    return true;
  }

  function focusNow(el){
    try { el.focus({ preventScroll: true }); }
    catch(_) { try { el.focus(); } catch(__){} }
  }

  function schedule(target, { delay = 0, tries = 8, interval = 40 } = {}){
    const el = typeof target === 'string' ? $(target) : target;
    if (!el) return;

    token++;
    const myToken = token;
    if (timer) { clearTimeout(timer); timer = null; }

    const attempt = (left) => {
      if (myToken !== token) return; // superseded
      if (isVisible(el)) { focusNow(el); return; }
      if (left <= 0) return;
      timer = setTimeout(()=>attempt(left-1), interval);
    };

    const start = () => attempt(tries);
    if (delay > 0) timer = setTimeout(start, delay);
    else if (typeof requestAnimationFrame === 'function') requestAnimationFrame(()=> setTimeout(start, 0));
    else start();
  }

  return { schedule };
})();
const autoFocus = (idOrEl, opts) => focusManager.schedule(idOrEl, opts);

/* ----------------------------------------------------------
   i18n helpers & dynamic substitutions
---------------------------------------------------------- */
function _t_safe(k){ try{ return window._t ? window._t(k) : (k||''); } catch(_){ return k||''; } }

/* Build nested accordions from .faq-blocks (kept) */
function buildDetailsFromBlocks(blocks){
  const frag = document.createDocumentFragment();
  blocks.forEach(block=>{
    const clone = block.cloneNode(true);
    const titleEl = clone.querySelector('h4,h3,h5,h2,.q,[data-q]');
    const title = titleEl ? titleEl.textContent.trim() : '…';
    if (titleEl) titleEl.remove();

    const details = document.createElement('details');
    details.className = 'faq-item';

    const summary = document.createElement('summary');
    summary.textContent = title;
    details.appendChild(summary);

    const body = document.createElement('div');
    body.className = 'faq-item-body';
    Array.from(clone.childNodes).forEach(n=>body.appendChild(n));
    details.appendChild(body);

    frag.appendChild(details);
  });
  return frag;
}
function enhanceFaqNestedAccordions(){
  try{
    document.querySelectorAll('#faqModal .acc-content').forEach(section=>{
      const blocks = Array.from(section.querySelectorAll('.faq-block'));
      if (!blocks.length) return;
      const holder = document.createElement('div');
      holder.className = 'faq-items';
      holder.appendChild(buildDetailsFromBlocks(blocks));
      section.innerHTML = '';
      section.appendChild(holder);
    });
  }catch(e){}
}
function enhancePostApprovalAccordions(){
  try{
    document.querySelectorAll('#completionModal .acc-content').forEach(section=>{
      const blocks = Array.from(section.querySelectorAll('.faq-block'));
      if (!blocks.length) return;
      const holder = document.createElement('div');
      holder.className = 'faq-items';
      holder.appendChild(buildDetailsFromBlocks(blocks));
      section.innerHTML = '';
      section.appendChild(holder);
    });
  }catch(e){}
}

/* Apply static texts + dynamic {btn} token in subtitle */
function applyTexts(){
  document.querySelectorAll('[data-i18n]').forEach(el=>{
    el.textContent = _t_safe(el.dataset.i18n);
  });
  document.querySelectorAll('[data-i18n-html]').forEach(el=>{
    el.innerHTML = _t_safe(el.dataset.i18nHtml);
  });
  const ce = $('chatEditor');
  if (ce) ce.setAttribute('placeholder', _t_safe('CHAT_PLACEHOLDER'));

  // Dynamic substitution: replace {btn} with the localized “send code” label
  const sub = document.querySelector('[data-i18n="OTP_SUBTITLE"]');
  if (sub){
    let tpl = _t_safe('OTP_SUBTITLE');
    sub.innerHTML = (tpl || '').replace('{btn}', _t_safe('OTP_RESEND_BTN'));
  }

  enhanceFaqNestedAccordions();
  enhancePostApprovalAccordions();
}

// Apply translations after DOM is ready and all scripts have loaded
document.addEventListener('DOMContentLoaded', () => {
  // Small delay to ensure all deferred scripts have run
  setTimeout(applyTexts, 0);
});

/* ----------------------------------------------------------
   Sidebar toggle (unchanged)
---------------------------------------------------------- */
const menuBtn = $('menuBtn');
if (menuBtn) {
  menuBtn.onclick = () => $('sidebar').classList.toggle('open');
  // Hide menu button initially (until portal UI loads)
  menuBtn.style.display = 'none';
}
function maybeCloseSidebar(){ if (window.innerWidth <= 1024) $('sidebar')?.classList.remove('open'); }

/* ----------------------------------------------------------
   Intro modal (unchanged)
---------------------------------------------------------- */
function openIntro(){ if (SHOW_INTRO && $('videoFrame')) $('videoFrame').src = ytUrlWithSafeParams(VIDEO_URL); show($('introModal')); }
function closeIntro(){ const f=$('videoFrame'); if(f) f.src=''; hide($('introModal')); if (shouldStartTour && !tourActive && typeof startTour==='function') startTour(); }
const introBtn=$('introBtn'); if (introBtn) introBtn.onclick=openIntro;
const introX=$('introCloseBtn'); if (introX) introX.onclick=closeIntro;
const introOkay=$('introOkayBtn'); if (introOkay) introOkay.onclick=closeIntro;
const introOverlay=$('introModal'); if (introOverlay) introOverlay.onclick=e=>{ if(e.target&&e.target.id==='introModal') closeIntro(); };
window.addEventListener('keydown', e=>{ if(e.key==='Escape' && !$('introModal')?.classList.contains('hidden')) closeIntro(); });
if (!SHOW_INTRO){ const vw=document.querySelector('.video-wrapper'); if (vw) vw.classList.add('hidden'); }

/* ----------------------------------------------------------
   FAQ modal (unchanged)
---------------------------------------------------------- */
function openFAQ(){ enhanceFaqNestedAccordions(); show($('faqModal')); }
function closeFAQ(){ hide($('faqModal')); }
(function initFaqButton(){
  const btn=$('faqBtn'); if (!btn) return;
  if (SHOW_FAQ){ btn.classList.remove('hidden'); btn.onclick=openFAQ; }
  else { btn.classList.add('hidden'); btn.onclick=null; }
})();
if ($('faqCloseBtn')) $('faqCloseBtn').onclick = closeFAQ;
if ($('faqOkayBtn'))  $('faqOkayBtn').onclick  = closeFAQ;
if ($('faqModal'))    $('faqModal').onclick    = e=>{ if(e.target.id==='faqModal') closeFAQ(); };
document.querySelectorAll('.acc-header').forEach(btn=>{
  btn.onclick = ()=>{
    btn.classList.toggle('open');
    const c = btn.nextElementSibling;
    if(c) c.classList.toggle('hidden');
  };
});

/* ----------------------------------------------------------
   Completion modal (unchanged content, new buttons wired below)
---------------------------------------------------------- */
function openCompletion(){ enhancePostApprovalAccordions(); show($('completionModal')); }
function closeCompletion(){ hide($('completionModal')); }
if ($('completionCloseBtn')) $('completionCloseBtn').onclick = closeCompletion;
if ($('completionOkayBtn'))  $('completionOkayBtn').onclick  = closeCompletion;
if ($('completionModal'))    $('completionModal').onclick    = e=>{ if(e.target.id==='completionModal') closeCompletion(); };
if ($('viewCompletionBtn'))  $('viewCompletionBtn').onclick  = openCompletion;

/* ----------------------------------------------------------
   McPhone normalization (ported)
   Returns { digits: '45xxxxxxxx', ok: boolean, warning: string|null, e164: '+45xxxxxxxx' }
---------------------------------------------------------- */
function mcNormDK(raw){
  const out = { digits:null, ok:false, warning:null, e164:'' };
  if (!raw || !raw.trim()){ out.warning='Blank input'; return out; }
  let digits = raw.replace(/[^0-9]/g,'');
  if (!digits){ out.warning='No digits found'; return out; }
  if (digits.startsWith('0045')) digits = '45' + digits.substring(4);
  // Handle double-prefix: 4545... → 45...
  if (digits.startsWith('4545') && digits.length >= 12) digits = digits.substring(2);
  if (digits.length === 8) digits = '45' + digits;
  const ok = (digits.startsWith('45') && digits.length === 10);
  out.digits = digits; out.ok = ok; out.warning = ok?null:'DK sanity check failed (expect 45 + 8 digits)'; out.e164 = digits?('+'+digits):''; return out;
}
function mcNormSE(raw){
  const out = { digits:null, ok:false, warning:null, e164:'' };
  if (!raw || !raw.trim()){ out.warning='Blank input'; return out; }
  let digits = raw.replace(/[^0-9]/g,'');
  if (!digits){ out.warning='No digits found'; return out; }
  if (digits.startsWith('0046')) digits = '46' + digits.substring(4);
  // Handle double-prefix: 4646... → 46...
  else if (digits.startsWith('4646') && digits.length >= 12) digits = digits.substring(2);
  else if (digits.startsWith('46')) { /* ok */ }
  else if (digits.startsWith('0') && digits.length >= 2) digits = '46' + digits.substring(1);
  const ok = (digits.startsWith('46') && digits.length >= 10 && digits.length <= 12);
  out.digits = digits; out.ok = ok; out.warning = ok?null:'SE sanity check failed (expect starts with 46 and reasonable length)'; out.e164 = digits?('+'+digits):''; return out;
}
function mcNormIE(raw){
  const out = { digits:null, ok:false, warning:null, e164:'' };
  if (!raw || !raw.trim()){ out.warning='Blank input'; return out; }
  let digits = raw.replace(/[^0-9]/g,'');
  if (!digits){ out.warning='No digits found'; return out; }
  if (digits.startsWith('00353')) digits = '353' + digits.substring(5);
  // Handle double-prefix: 353353... → 353...
  else if (digits.startsWith('353353') && digits.length >= 16) digits = digits.substring(3);
  else if (digits.startsWith('353')) { /* ok */ }
  else if (digits.startsWith('0') && digits.length >= 2) digits = '353' + digits.substring(1);
  const ok = (digits.startsWith('353') && digits.length >= 12 && digits.length <= 13);
  out.digits = digits; out.ok = ok; out.warning = ok?null:'IE sanity check failed (expect starts with 353 and reasonable length)'; out.e164 = digits?('+'+digits):''; return out;
}
function mcNormalize(raw, iso){
  switch((iso||'').toUpperCase()){
    case 'DK': return mcNormDK(raw);
    case 'SE': return mcNormSE(raw);
    case 'IE': return mcNormIE(raw);
    default: {
      const digits = (raw||'').replace(/[^0-9]/g,'');
      return { digits, ok: !!digits, warning: digits?null:'Blank or no digits', e164: digits?('+'+digits):'' };
    }
  }
}

/* Country list for phone picker (Nordic + nearby) */
const PHONE_COUNTRIES = [
  { iso:'DK', dial:'45',  name:'Denmark' },
  { iso:'SE', dial:'46',  name:'Sweden' },
  { iso:'NO', dial:'47',  name:'Norway' },
  { iso:'DE', dial:'49',  name:'Germany' },
  { iso:'IE', dial:'353', name:'Ireland' },
  { iso:'NL', dial:'31',  name:'Netherlands' },
  { iso:'FI', dial:'358', name:'Finland' },
  { iso:'UK', dial:'44',  name:'United Kingdom' }
];

/* ----------------------------------------------------------
   OTP / Identifier logic
---------------------------------------------------------- */
function showStep(which){
  const idStep = $('idStep');
  const verifyStep = $('verifyStep');
  const subtitle = document.querySelector('[data-i18n="OTP_SUBTITLE"]');
  const idChooser = $('idChooser');
  
  if (which === 'verify'){ 
    hide(idStep); 
    show(verifyStep); 
    if (subtitle) hide(subtitle);
    if (idChooser) hide(idChooser);
    // Auto-focus OTP input when shown (visibility-aware, iOS-friendly)
    autoFocus('otp', { delay: 60, tries: 8, interval: 40 });
  } else { 
    show(idStep); 
    hide(verifyStep); 
    if (subtitle) show(subtitle);
    if (idChooser) show(idChooser);
  }
}
function setVerifySub(){
  const el = $('verifySub'); if (!el) return;
  const channel = (identifierType === 'phone')
    ? _t_safe('VERIFY_CHANNEL_PHONE')
    : _t_safe('VERIFY_CHANNEL_EMAIL');
  let tpl = _t_safe('VERIFY_SUB_TPL');
  try{ tpl = tpl.replace('{channel}', channel).replace('{value}', identifierValue || ''); }catch(_){}
  el.textContent = tpl;
}
function startOver(){
  const otpInput = $('otp');    if (otpInput) otpInput.value = '';
  const phoneLocal = $('phoneLocal'); if (phoneLocal) phoneLocal.value='';
  const emailInput = $('emailInput'); if (emailInput) emailInput.value='';
  identifierValue = ''; sessionToken = '';
  setMsg(''); setIdMsg('');
  showStep('auth');
  // Focus correct field after returning to identifier step
  if (identifierType === 'phone') autoFocus('phoneLocal', { delay: 60 });
  else                            autoFocus('emailInput', { delay: 60 });
}

async function requestOtpIdentifier(){
  // Gather input depending on channel
  let payload = { channel: identifierType, market: (window.__BRAND && window.__BRAND.market) || '' };

  if (identifierType === 'phone'){
    const phoneLocal = ($('phoneLocal')?.value || '').trim();
    const iso = $('phoneCountryBtn')?.dataset?.iso || DEFAULT_PHONE_ISO;
    const dial = (PHONE_COUNTRIES.find(c=>c.iso===iso) || PHONE_COUNTRIES[0]).dial;
    
    // Fix: Detect if user pasted full international number to avoid double prefix
    let raw = phoneLocal;
    if (raw.startsWith('+') || raw.startsWith('00')) {
      // Already international format, use as-is
      raw = raw;
    } else if (raw.startsWith(dial)) {
      // Already has dial code, prepend +
      raw = '+' + raw;
    } else {
      // Normal case: prepend full prefix
      raw = `+${dial}${raw}`;
    }
    
    const norm = mcNormalize(raw, iso);
    identifierValue = norm.e164 || raw;
    payload.phone       = norm.e164 || raw;
    payload.phoneDigits = norm.digits || '';
    payload.country     = iso;
  } else {
    const email = ($('emailInput')?.value || '').trim().toLowerCase();
    if (!email){ setIdMsg(_t_safe('OTP_INPUT_EMAIL')); return; }
    identifierValue = email;
    payload.email = email;
  }

  // UX: proceed to verify regardless of match result so backend can create OTP__c = "No Match" if applicable.
  setIdMsg(_t_safe('OTP_SENDING'));
  try{
    const r = await fetch(ID_REQUEST_OTP, {
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body: JSON.stringify(payload)
    });
    // ignore r.ok here on purpose (requirement #3)
    await r.json().catch(()=>({}));
  }catch(_){/* swallow */ }

  // Go to Verify
  setIdMsg(_t_safe('OTP_SENT'));
  setVerifySub();
  showStep('verify');           // this schedules focus on #otp
  // (Removed redundant immediate otp.focus() to avoid race conditions)
}

async function verifyOtpIdentifier(code){
  const iso = $('phoneCountryBtn')?.dataset?.iso || DEFAULT_PHONE_ISO;
  const payload = (identifierType === 'phone')
    ? { phone: identifierValue, otp: code, country: iso }
    : { email: identifierValue, otp: code };
  const r = await fetch(ID_VERIFY_OTP, { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(payload) });
  const j = await r.json().catch(()=>({}));
  if (!r.ok || !j.ok) throw Error(j.error || _t_safe('OTP_INVALID'));
  sessionToken = j.session || '';
  if (!sessionToken) throw Error('Session missing');
  
  // Start proactive session refresh timer
  startSessionRefreshTimer();
  
  // NEW: Fetch journals to determine if we need bridge page
  await fetchJournalsForIdentifier();
}

async function fetchJournalsForIdentifier() {
  try {
    const payload = (identifierType === 'phone')
      ? { phone: identifierValue }
      : { email: identifierValue };
    const r = await fetch(ID_LIST, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${sessionToken}`
      },
      body: JSON.stringify(payload)
    });
    const j = await r.json().catch(() => ({}));
    if (!r.ok || !j.ok) throw Error(j.error || 'Failed to fetch journals');
    
    console.log('fetchJournalsForIdentifier response:', j);
    
    // Check if journals array exists (new Lambda) or fallback to old behavior
    if (j.journals && Array.isArray(j.journals)) {
      availableJournals = j.journals;
      
      if (availableJournals.length === 0) {
        throw Error(_t_safe('NO_DOCUMENTS_FOUND') || 'No documents found');
      }
      // CHANGED: Always show bridge page (removed the single-journal skip logic)
      selectedJournalId = '';
    } else {
      // Old Lambda without journal grouping - extract journals from items
      console.warn('Lambda response missing journals array - using fallback logic');
      const items = j.items || [];
      if (items.length === 0) {
        throw Error(_t_safe('NO_DOCUMENTS_FOUND') || 'No documents found');
      }
      
      // Build journals from items
      const journalsMap = {};
      items.forEach(item => {
        const jId = item.journalId;
        const jName = item.journalName || jId;
        if (jId && !journalsMap[jId]) {
          journalsMap[jId] = {
            id: jId,
            name: jName,
            documentCount: 0
          };
        }
        if (jId) {
          journalsMap[jId].documentCount++;
        }
      });
      
      availableJournals = Object.values(journalsMap);
      
      if (availableJournals.length === 0) {
        throw Error(_t_safe('NO_DOCUMENTS_FOUND') || 'No documents found');
      }
      // CHANGED: Always show bridge page
      selectedJournalId = '';
    }
  } catch (err) {
    console.error('fetchJournalsForIdentifier error:', err);
    throw err;
  }
}

async function verifyOtpJournal(code){
  const r = await fetch(OTP_VERIFY,{
    method:'POST',
    headers:{'Content-Type':'application/json'},
    body:JSON.stringify({externalId,otp:code})
  });
  const j = await r.json().catch(()=>({}));
  if(!r.ok||!j.ok) throw Error(j.error||_t_safe('OTP_INVALID'));
}

async function resendOtp(){
  if (MODE === 'journal'){
    const r = await fetch(OTP_SEND,{ method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({externalId}) });
    const j = await r.json().catch(()=>({}));
    if(!r.ok||!j.ok) throw Error(j.error||_t_safe('OTP_RESEND_FAILED'));
  } else {
    await requestOtpIdentifier();
  }
}

/* ----------------------------------------------------------
   Document helpers
---------------------------------------------------------- */
function getDocName(d){ return d.name || d.fileName || d.filename || d.key || 'Document'; }
function getSortField(d){
  const v = d.sortOrder ?? d.SortOrder ?? d.sort_order ?? d.displayOrder ?? d.DisplayOrder ?? d.order ?? d.Order ?? d.sequence ?? d.Sequence;
  if (v === null || v === undefined) return Number.MAX_SAFE_INTEGER;
  const n = typeof v === 'number' ? v : parseInt(String(v), 10);
  return Number.isFinite(n) ? n : Number.MAX_SAFE_INTEGER;
}
async function fetchDocs(){
  if (MODE === 'journal'){
    const r = await fetch(DOC_LIST,{ method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({externalId,accessToken}) });
    const j = await r.json().catch(()=>({}));
    if (isSessionExpired(r, j)) { handleSessionExpired(); return; }
    if(!r.ok||!j.ok) throw Error(_t_safe('LIST_FAILED'));
    docs = (j.documents || []);
  } else {
    // For impersonation mode, only send journalId (session has jid claim)
    const payload = impersonationMode 
      ? { journalId: selectedJournalId }
      : (identifierType === 'phone') ? { phone: identifierValue } : { email: identifierValue };
    
    // Add journal filter if selected (for non-impersonation)
    if (selectedJournalId && !impersonationMode) {
      payload.journalId = selectedJournalId;
    }
    
    const r = await fetch(ID_LIST,{ method:'POST', headers:{'Content-Type':'application/json','Authorization':`Bearer ${sessionToken}`}, body:JSON.stringify(payload) });
    const j = await r.json().catch(()=>({}));
    if (isSessionExpired(r, j)) { handleSessionExpired(); return; }
    if(!r.ok||!j.ok) throw Error(_t_safe('LIST_FAILED'));
    docs = (j.items || []);
  }
  docs = docs
    .filter(d => d.isNewestVersion)
    .sort((a,b)=>{
      const sa = getSortField(a), sb = getSortField(b);
      if (sa !== sb) return sa - sb;
      return getDocName(a).localeCompare(getDocName(b), undefined, {numeric:true, sensitivity:'base'});
    });
  if(!docs.length) throw Error(_t_safe('NO_DOCS_NEWEST'));
}
async function presign(id){
  if (MODE === 'journal'){
    const r = await fetch(DOC_URL,{ method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({externalId,accessToken,docId:id}) });
    const j = await r.json().catch(()=>({}));
    if (isSessionExpired(r, j)) { handleSessionExpired(); throw Error('Session expired'); }
    if(!r.ok||!j.ok) throw Error(_t_safe('PRESIGN_FAILED'));
    return j.url;
  } else {
    const r = await fetch(ID_DOC_URL,{ method:'POST', headers:{'Content-Type':'application/json','Authorization':`Bearer ${sessionToken}`}, body:JSON.stringify({docId:id}) });
    const j = await r.json().catch(()=>({}));
    if (isSessionExpired(r, j)) { handleSessionExpired(); throw Error('Session expired'); }
    if(!r.ok||!j.ok) throw Error(_t_safe('PRESIGN_FAILED'));
    return j.url;
  }
}

/* ----------------------------------------------------------
   Sidebar render (unchanged)
---------------------------------------------------------- */
function renderLists(){
  const pending  = docs.filter(d=>d.status!=='Approved'),
        approved = docs.filter(d=>d.status==='Approved');

  if ($('pendingCount'))  $('pendingCount').textContent  = pending.length;
  if ($('approvedCount')) $('approvedCount').textContent = approved.length;

  const render = (el,list,emptyKey)=>{
    if (!el) return;
    el.innerHTML='';
    if(!list.length){
      const p=document.createElement('div');
      p.className='doc-empty';
      p.textContent=_t_safe(emptyKey);
      el.appendChild(p);
      return;
    }
    list.forEach(doc=>{
      const div=document.createElement('div');
      div.className='doc-item'+(doc.status==='Approved'?' approved':'')+(doc===docs[active]?' active':'');
      
      // Add warning icon for blocked approval
      if (doc.isApprovalBlocked) {
        const warningIcon = document.createElement('span');
        warningIcon.textContent = '⚠️ ';
        warningIcon.style.marginRight = '4px';
        div.appendChild(warningIcon);
        div.title = _t('APPROVAL_BLOCKED_TOOLTIP');
      }
      
      // Show only document type (no filename)
      const textNode = document.createTextNode(doc.documentType || getDocName(doc));
      div.appendChild(textNode);
      
      div.onclick=()=>{
        maybeCloseSidebar();
        active=docs.indexOf(doc);
        renderLists();
        loadCurrent();
        if (tourActive && typeof tour!=='undefined' && tour.state === 'waitForDocClick') tour.next();
      };
      el.appendChild(div);
    });
  };
  render($('pendingList'),pending,'PENDING_EMPTY');
  render($('approvedList'),approved,'APPROVED_EMPTY');
  if ($('approveAllBtn')) $('approveAllBtn').classList.toggle('hidden', !SHOW_APPROVE_ALL || !pending.length);
}

/* ----------------------------------------------------------
   Viewer + actions (download/print only on click)
---------------------------------------------------------- */
async function loadCurrent(){
  // Guard: Validate docs array and active index before accessing
  if (!docs || !Array.isArray(docs) || docs.length === 0) {
    console.warn('loadCurrent: docs array is empty or undefined');
    setMsg(_t_safe('NO_DOCUMENTS_FOUND') || 'No documents available');
    spin(false);
    return;
  }
  
  if (active < 0 || active >= docs.length) {
    console.warn(`loadCurrent: active index ${active} is out of bounds (docs.length=${docs.length})`);
    active = 0; // Reset to first document
    if (docs.length === 0) {
      setMsg(_t_safe('NO_DOCUMENTS_FOUND') || 'No documents available');
      spin(false);
      return;
    }
  }
  
  // Check session validity before expensive operations
  if (!isSessionValid()) {
    console.warn('loadCurrent: session expired, triggering session handler');
    handleSessionExpired();
    return;
  }
  
  try{
    setMsg(_t_safe('LOADING')); if ($('pdf')) $('pdf').src='';
    spin(true);
    
    currentPresigned = await presign(docs[active].id);
    if ($('pdf')) $('pdf').src=currentPresigned+'#toolbar=0&zoom=150';
    setMsg('');
    try{
      if(docs[active].status === 'Sent'){
        docs[active].status = 'Viewed';
        renderLists();
      }
    }catch(_){}
  }catch(e){ setMsg(e.message);}finally{ spin(false); }

  const doc   = docs[active],
        allOk = docs.every(d=>d.status==='Approved'),
        curOk = doc.status==='Approved';

  if ($('headerText')) $('headerText').textContent = allOk ? _t_safe('HEADER_ALL_OK') : _t_safe('HEADER_PENDING');
  if ($('viewCompletionBtn')) $('viewCompletionBtn').classList.toggle('hidden', !allOk);

  const docType = doc.documentType || getDocName(doc);
  
  // IMPERSONATION: Hide approval button if in read-only mode
  if (impersonationMode && !impersonationAllowApprove) {
    hide($('approveRow'));
  } else {
    show($('approveRow'));
  }
  
  if ($('approveBtn') && $('approveMsg')){
    if (doc.isApprovalBlocked){
      $('approveBtn').classList.add('blocked-approval');
      $('approveBtn').textContent = `${_t_safe('APPROVE_PREFIX')} ${docType}`;
      $('approveBtn').disabled = false;
      const hintText = _t_safe('APPROVAL_BLOCKED_HINT');
      $('approveMsg').innerHTML = `<span style="color:var(--danger)">${hintText}</span>`;
    }else if (curOk){
      $('approveBtn').classList.remove('blocked-approval');
      $('approveBtn').textContent = `${docType} er godkendt`;
      $('approveBtn').disabled = true;
      $('approveMsg').textContent = '';
    }else{
      $('approveBtn').classList.remove('blocked-approval');
      $('approveBtn').textContent = `${_t_safe('APPROVE_PREFIX')} ${docType}`;
      $('approveBtn').disabled = false;
      $('approveMsg').textContent = '';
    }
  }

  if(allOk && !completionShown){
    completionShown = true;
    openCompletion();
  }
}

/* shared handlers for download/print – triggered only by user click */
function doDownload(){
  try{
    const a=document.createElement('a');
    a.href=currentPresigned; a.download='document.pdf'; a.target='_blank';
    document.body.appendChild(a); a.click(); a.remove();
  }catch(e){ console.error(e); }
}
async function doPrint(){
  if (!currentPresigned) {
    try { $('pdf')?.contentWindow?.print?.(); } catch {}
    return;
  }
  
  // Try using the existing PDF iframe first
  try {
    const pdfFrame = $('pdf');
    if (pdfFrame && pdfFrame.contentWindow) {
      pdfFrame.contentWindow.focus();
      pdfFrame.contentWindow.print();
      return;
    }
  } catch (e) {
    console.log('Direct iframe print failed, trying blob method:', e);
  }
  
  // Fallback: fetch and create blob URL
  try {
    const res = await fetch(currentPresigned, { mode: 'cors', credentials: 'omit' });
    if (!res.ok) throw new Error('PDF fetch failed');
    const blob = await res.blob();
    const url = URL.createObjectURL(blob);
    const frame = document.createElement('iframe');
    frame.style.position='fixed'; frame.style.right='0'; frame.style.bottom='0'; frame.style.width='0'; frame.style.height='0'; frame.style.border='0';
    const cleanup=()=>{ try{URL.revokeObjectURL(url);}catch{} try{frame.remove();}catch{} };
    frame.onload = () => {
      const cw = frame.contentWindow; if(!cw) return cleanup();
      const cleanOnce = () => { cw.removeEventListener('afterprint', cleanOnce); window.removeEventListener('afterprint', cleanOnce); setTimeout(cleanup, 1000); };
      cw.addEventListener('afterprint', cleanOnce, { once: true });
      window.addEventListener('afterprint', cleanOnce, { once: true });
      try { cw.focus(); } catch {}
      cw.print();
      setTimeout(cleanOnce, 120000);
    };
    frame.src = url; document.body.appendChild(frame);
  } catch (err) {
    console.error('Blob print method failed:', err);
    // Last resort: open in new window
    window.open(currentPresigned, '_blank');
  }
}

if ($('downloadBtn')) $('downloadBtn').onclick = doDownload;
if ($('printBtn'))    $('printBtn').onclick    = doPrint;
// Also expose the same actions inside the completion modal
if ($('completionDownloadBtn')) $('completionDownloadBtn').onclick = doDownload;
if ($('completionPrintBtn'))    $('completionPrintBtn').onclick    = doPrint;

/* ----------------------------------------------------------
   Approval modal + Approve handler
---------------------------------------------------------- */
let modalResolve=null;
function openApproval(ids){
  const many=ids.length>1,
        docsToShow=docs.filter(d=>ids.includes(d.id)),
        list=many?`<ul>${docsToShow.map(d=>`<li>${getDocName(d)}</li>`).join('')}</ul>`:'';

  if ($('confirmText')) $('confirmText').innerHTML = many
    ? `${_t_safe('MODAL_APPROVE_ALL_TXT')} ${list}`
    : `${_t_safe('MODAL_APPROVE_TXT')} <strong>${getDocName(docsToShow[0])}</strong>.`;
  if ($('confirmApprove')) $('confirmApprove').textContent = many?_t_safe('MODAL_APPROVE_ALL'):_t_safe('MODAL_APPROVE');
  show($('confirmModal'));
  return new Promise(res=>{modalResolve=res;});
}
if ($('confirmCancel' )) $('confirmCancel' ).onclick=()=>{hide($('confirmModal'));modalResolve(false);};
if ($('confirmCancel2')) $('confirmCancel2').onclick=()=>{hide($('confirmModal'));modalResolve(false);};
if ($('confirmApprove')) $('confirmApprove').onclick=()=>{hide($('confirmModal'));modalResolve(true);};

/* ----------------------------------------------------------
   Blocked Approval Modal
---------------------------------------------------------- */
function openBlockedApprovalModal(){
  const modal = $('confirmModal');
  const text = $('confirmText');
  const approveBtn = $('confirmApprove');
  const cancelBtn = $('confirmCancel2');
  
  text.innerHTML = `
    <h3 style="margin-top:0">${_t_safe('BLOCKED_APPROVAL_HEADER')}</h3>
    <p>${_t_safe('BLOCKED_APPROVAL_BODY')}</p>
  `;
  
  if (approveBtn) approveBtn.style.display = 'none';
  if (cancelBtn) cancelBtn.textContent = _t_safe('CLOSE');
  
  show(modal);
  
  // Restore approve button when modal closes
  const restore = () => {
    if (approveBtn) approveBtn.style.display = '';
    modal.removeEventListener('click', clickHandler);
  };
  
  const clickHandler = (e) => {
    if (e.target === $('confirmCancel') || e.target === $('confirmCancel2')) {
      restore();
    }
  };
  
  modal.addEventListener('click', clickHandler);
}

async function tryApprove(ids){
  // Check for blocked documents first
  const blocked = docs.filter(d => ids.includes(d.id) && d.isApprovalBlocked);
  if (blocked.length > 0) {
    openBlockedApprovalModal();
    return;
  }
  
  if(!await openApproval(ids)) return;
  if ($('approveMsg')) $('approveMsg').textContent=_t_safe('GENERIC_SENDING');

  if (MODE === 'journal'){
    const r=await fetch(APPROVE_URL,{ method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({externalId,accessToken,docIds:ids}) });
    const j=await r.json().catch(()=>({}));
    if (isSessionExpired(r, j)) { handleSessionExpired(); return; }
    const ok=r.ok&&j.ok;
    if(ok){
      ids.forEach(id=>{const d=docs.find(x=>x.id===id); if(d) d.status='Approved';});
      renderLists();await loadCurrent(); if ($('approveMsg')) $('approveMsg').textContent=_t_safe('APPROVE_THANKS');
    }else{ if ($('approveMsg')) $('approveMsg').textContent=_t_safe('GENERIC_ERROR'); }
  } else {
    const r=await fetch(ID_APPROVE,{ method:'POST', headers:{'Content-Type':'application/json','Authorization':`Bearer ${sessionToken}`}, body:JSON.stringify({docIds:ids}) });
    const j=await r.json().catch(()=>({}));
    if (isSessionExpired(r, j)) { handleSessionExpired(); return; }
    if(r.ok && j.ok){
      ids.forEach(id=>{const d=docs.find(x=>x.id===id); if(d) d.status='Approved';});
      renderLists();await loadCurrent(); if ($('approveMsg')) $('approveMsg').textContent=_t_safe('APPROVE_THANKS');
    }else{ if ($('approveMsg')) $('approveMsg').textContent=j.error || _t_safe('GENERIC_ERROR'); }
  }
}

/* ----------------------------------------------------------
   Chat (document-scoped)
---------------------------------------------------------- */
const chatSeen=new Set(),chatCache=[];
function renderChat(){
  const box=$('chatList');
  if(!box) return;
  if(!chatCache.length){
    box.innerHTML = `
      <div style="text-align:center; padding:40px 20px; color:#999;">
        <p style="font-size:18px; margin:0 0 10px;">📭</p>
        <p style="margin:0;">${_t_safe('CHAT_EMPTY')}</p>
      </div>
    `;
    return;
  }
  box.innerHTML='';
  chatCache.forEach(m=>{
    const wrap=document.createElement('div'), ts=document.createElement('div'), row=document.createElement('div');
    wrap.className=(m.inbound||m.Is_Inbound__c)?'me':'them';
    ts.className='chat-ts'; ts.textContent=new Date(m.at||m.createdDate||Date.now()).toLocaleString();
    row.className='chat-row'; row.innerHTML=m.body;
    wrap.appendChild(row); box.appendChild(ts); box.appendChild(wrap);
  });
  box.scrollTop=box.scrollHeight;
}
async function fetchChat(){
  try {
    let url, options;
    if (MODE === 'journal') {
      // Journal mode: use query parameters
      url = `${CHAT_LIST}?e=${encodeURIComponent(externalId)}&t=${encodeURIComponent(accessToken)}`;
      options = { method: 'GET' };
    } else {
      // Identifier mode: POST with Bearer token and selected journal
      url = `${API}/identifier/chat/list`;
      options = {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${sessionToken}`
        },
        body: JSON.stringify({ journalId: selectedJournalId })
      };
    }
    
    const r = await fetch(url, options);
    const j = await r.json().catch(()=>({}));
    if (isSessionExpired(r, j)) { handleSessionExpired(); return; }
    if(!r.ok||!j.ok) return;
    
    j.messages.forEach(m=>{
      if(chatSeen.has(m.id)) return;
      chatSeen.add(m.id);
      chatCache.push(m);
    });
    renderChat();
  } catch(e) {
    console.error('fetchChat error:', e);
  }
}
async function sendChat(){
  const ed=$('chatEditor'), html=(ed?.innerHTML || '').trim();
  if(!html) return;
  
  ed.setAttribute('contenteditable','false');
  ed.textContent=_t_safe('GENERIC_SENDING');
  
  try {
    let url, options;
    if (MODE === 'journal') {
      url = CHAT_SEND;
      options = {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          externalId,
          accessToken,
          body: html
        })
      };
    } else {
      // Identifier mode: POST with Bearer token and journal ID
      url = `${API}/identifier/chat/send`;
      options = {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${sessionToken}`
        },
        body: JSON.stringify({
          journalId: selectedJournalId,
          body: html
        })
      };
    }
    
    const r = await fetch(url, options);
    const j = await r.json().catch(()=>({}));
    if (isSessionExpired(r, j)) { handleSessionExpired(); return; }
    
    ed.setAttribute('contenteditable','true');
    ed.innerHTML='';
    fetchChat();
  } catch(e) {
    console.error('sendChat error:', e);
    ed.setAttribute('contenteditable','true');
  }
}
document.querySelectorAll('.chat-tools button').forEach(b=>b.onclick=()=>document.execCommand(b.dataset.cmd,false));

function openChatPanel(source='user'){
  const panel=$('chatPanel'), label=$('chatLabel'), header=$('chatHeader');
  if (!panel || !header) return;
  
  panel.style.display='flex'; panel.classList.remove('hidden'); header.textContent = _t_safe('CHAT_HEADER_OPEN');
  if (label){ label.style.display='none'; label.classList.add('hidden'); }
  
  // Clear old messages when switching journals
  chatCache.length = 0;
  chatSeen.clear();
  
  fetchChat();
  if (source === 'user') { try { localStorage.setItem(CHAT_SEEN_KEY,'1'); } catch(e){} }
}

function closeChatPanel(){
  const panel=$('chatPanel'), label=$('chatLabel'), header=$('chatHeader');
  if (!panel || !header) return;
  panel.style.display='none'; panel.classList.add('hidden'); header.textContent = _t_safe('CHAT_HEADER');
  if (!hasSeenLabel()){ if(label){ label.classList.remove('hidden'); label.style.display='block'; positionChatLabel(); } }
  else { if(label){ label.style.display='none'; label.classList.add('hidden'); } }
}

if ($('chatFab'))    $('chatFab').onclick=()=>{ if($('chatPanel')?.style.display==='flex'){ closeChatPanel(); } else { openChatPanel('user'); } };
if ($('chatHeader')) $('chatHeader').onclick=()=>{ if($('chatPanel')?.style.display==='flex'){ closeChatPanel(); } };
if ($('chatLabel'))  $('chatLabel').onclick = () => openChatPanel('user');
if ($('chatSend'))   $('chatSend').onclick=sendChat;
if ($('chatEditor')) $('chatEditor').addEventListener('keydown',e=>{ if(e.key==='Enter'&&e.ctrlKey) sendChat(); });

/* Chat disclaimer close button */
const CHAT_DISCLAIMER_KEY = 'dfj_chat_disclaimer_dismissed';
if ($('chatDisclaimerClose')) {
  $('chatDisclaimerClose').onclick = () => {
    const disclaimer = $('chatDisclaimer');
    if (disclaimer) {
      disclaimer.classList.add('hidden');
      try { localStorage.setItem(CHAT_DISCLAIMER_KEY, '1'); } catch(e){}
    }
  };
}

/* Check if disclaimer was previously dismissed */
function showChatDisclaimer() {
  try {
    const dismissed = localStorage.getItem(CHAT_DISCLAIMER_KEY);
    const disclaimer = $('chatDisclaimer');
    if (disclaimer && dismissed === '1') {
      disclaimer.classList.add('hidden');
    }
  } catch(e){}
}
showChatDisclaimer();

/* NEW: robust positioning that does not "grow" on scroll.
   - Anchor horizontally using 'right' so width never feeds back into the calc.
   - Measure natural size first to get correct height for vertical centering. */
function positionChatLabel(){
  const fab=$('chatFab'), label=$('chatLabel');
  if (!fab || !label) return;
  if (label.classList.contains('hidden')) return;

  const fr = fab.getBoundingClientRect();

  // Ensure we can measure intrinsic size without feedback loops
  const prev = {
    display: label.style.display,
    left: label.style.left,
    right: label.style.right,
    width: label.style.width
  };
  if (prev.display === 'none') label.style.display = 'block';

  // Reset horizontal positioning for a clean measurement
  label.style.left  = 'auto';
  label.style.right = 'auto';
  label.style.width = 'auto';

  const lr = label.getBoundingClientRect();

  const GAP = 12;
  // Right distance from viewport edge to label's right edge
  const rightPx = Math.max(0, window.innerWidth - fr.left + GAP);
  label.style.right = rightPx + 'px';   // ← independent of label width
  label.style.left  = 'auto';

  // Vertical: center against FAB
  label.style.top = (fr.top + (fr.height - lr.height)/2) + 'px';

  // restore original display if we temporarily changed it
  label.style.display = prev.display;
}
window.addEventListener('resize', positionChatLabel);
window.addEventListener('scroll', positionChatLabel, { passive: true });
// Note: FAB is fixed; scroll listener only handles mobile UI bars resizing.

/* ----------------------------------------------------------
   In-app guidance tour
   (Chat opens at start, stays open during tour, closes when finished)
   - Added FAQ step (3rd) — but only if SHOW_FAQ = true
   - Styled buttons: Done = green-ish, Close = red-ish
---------------------------------------------------------- */
const tour = {
  idx: 0,
  state: '',
  steps: (function buildSteps(){
    const arr = [
      { key:'SIDEBAR',   target:'#sidebar',   textKey:'TOUR_STEP_SIDEBAR', advanceOn:'docClick' }, // 1
      { key:'PDF',       target:'#pdf',       textKey:'TOUR_STEP_PDF' }                            // 2
    ];
    if (SHOW_INTRO) {  // Use SHOW_INTRO instead of SHOW_FAQ for FAQ visibility
      const faqBtn = $('faqBtn');
      if (faqBtn && !faqBtn.classList.contains('hidden')) {
        arr.push({ key:'FAQ', target:'#faqBtn', textKey:'TOUR_STEP_FAQ' });  // 3 (conditional)
      }
    }
    arr.push(
      // 4
      { key:'CHAT',      target:'#chatPanel', textKey:'TOUR_STEP_CHAT', openChat:true, leftOf:true, nudgeX:-100 },
      // 5
      { key:'APPROVE',   target:'#approveBtn', textKey:'TOUR_STEP_APPROVE', showApprove:true, leftOf:true, nudgeY:-120 },
      // 6
      { key:'DOWNLOAD',  target:['#printBtn','#downloadBtn'], textKey:'TOUR_STEP_DOWNLOAD', below:true, wide:true }
    );
    return arr;
  })(),
  start(){
    tourActive = true;

    // Open chat at the very start (tour-driven, not user)
    openChatPanel('tour');

    // Style buttons: Done (green-ish), Close (red-ish)
    (function styleGuideButtons(){
      const done  = $('tourDoneBtn');
      const close = $('tourCloseBtn');
      if (done){
        // make it look like a green primary
        done.classList.remove('ghost');
        done.classList.add('primary');
        done.style.background = 'var(--ok)';
        done.style.border     = '1px solid var(--ok)';
        done.style.color      = '#fff';
      }
      if (close){
        // red-ish ghost
        close.classList.remove('primary');
        close.classList.add('ghost');
        close.style.background = '#fee2e2';
        close.style.border     = '1px solid #fecaca';
        close.style.color      = '#991b1b';
      }
    })();

    show($('tourDim')); show($('tourRing')); show($('tourTip'));
    this.idx = 0;
    this.showStep();
  },
  end(){
    tourActive = false;
    this.state = '';
    hide($('tourDim')); hide($('tourRing')); hide($('tourTip'));

    // Close chat when the tour ends
    closeChatPanel();

    // restore approve row to correct state
    loadCurrent();
  },
  showStep(){
    const s = this.steps[this.idx];
    if(!s) return this.end();

    // Keep chat open if step requests it (idempotent)
    if(s.openChat){ openChatPanel('tour'); }

    // ensure Approve row shows correctly when guide highlights it
    if (s.showApprove){
      const doc = docs[active];
      const name = (doc.name||doc.fileName||doc.filename||doc.key||'Document');
      show($('approveRow'));
      if (doc.status === 'Approved'){
        $('approveBtn').textContent = `${name} er godkendt`;
        $('approveBtn').disabled = true;
      }else{
        $('approveBtn').textContent = `${_t('APPROVE_PREFIX')} ${name}`;
        $('approveBtn').disabled = false;
      }
    }

    const targets = Array.isArray(s.target) ? s.target : [s.target];
    const els = targets.map(t => document.querySelector(t)).filter(Boolean);
    if(!els.length){ this.next(); return; }

    // Aggregate a rectangle that covers all targets
    const pad = 8;
    const rects = els.map(el => el.getBoundingClientRect());
    const agg = rects.reduce((a,r)=>({
      left: Math.min(a.left, r.left),
      top: Math.min(a.top, r.top),
      right: Math.max(a.right, r.right),
      bottom: Math.max(a.bottom, r.bottom)
    }), {left:Infinity, top:Infinity, right:-Infinity, bottom:-Infinity});
    const r = {
      left: agg.left,
      top: agg.top,
      right: agg.right,
      bottom: agg.bottom,
      width: agg.right - agg.left,
      height: agg.bottom - agg.top
    };

    // position ring
    const ring = $('tourRing');
    ring.style.left   = (r.left - pad) + 'px';
    ring.style.top    = (r.top  - pad) + 'px';
    ring.style.width  = (r.width  + pad*2) + 'px';
    ring.style.height = (r.height + pad*2) + 'px';

    // place tip
    const tip = $('tourTip');
    const tipW = s.wide ? 420 : 340;
    const tipText = s.text || _t(s.textKey); // allow literal text for new step
    $('tourTipText').textContent = tipText;
    $('tourCounter').textContent = `${this.idx+1}/${this.steps.length}`;
    let left = Math.min(window.innerWidth - tipW - 16, r.left + r.width + 12);
    let top  = Math.max(16, r.top);

    // left-of (used for CHAT and APPROVE so it doesn't overlap)
    if (s.leftOf){
      left = Math.max(16, r.left - tipW - 12);
      top  = Math.max(16, r.top);
    }
    // below target (for Print/Download buttons to avoid overlap)
    if (s.below){
      left = Math.min(window.innerWidth - tipW - 16, Math.max(16, r.left + (r.width - tipW)/2));
      top  = r.bottom + 12;
    }

    // Optional nudges (fine-grained placement)
    if (typeof s.nudgeX === 'number') left += s.nudgeX;
    if (typeof s.nudgeY === 'number') top  += s.nudgeY;

    tip.style.left = left + 'px';
    tip.style.top  = top  + 'px';

    // set state for special advancing
    this.state = (s.advanceOn === 'docClick') ? 'waitForDocClick' : '';

    // buttons visibility
    $('tourBackBtn').style.display  = (this.idx > 0) ? 'inline-block' : 'none';
    $('tourNextBtn').style.display  = (this.idx < this.steps.length - 1) ? 'inline-block' : 'none';
    $('tourDoneBtn').style.display  = (this.idx === this.steps.length - 1) ? 'inline-block' : 'none';
  },
  next(){ this.idx++; if(this.idx >= this.steps.length) return this.end(); this.showStep(); },
  prev(){ if (this.idx === 0) return; this.idx--; this.showStep(); }
};

$('tourNextBtn').onclick  = ()=>tour.next();
$('tourBackBtn').onclick  = ()=>tour.prev();
$('tourDoneBtn').onclick  = ()=>tour.end();
$('tourCloseBtn').onclick = ()=>tour.end();
// Allow closing the guide by clicking the dim background or pressing ESC
$('tourDim').onclick = ()=>tour.end();
window.addEventListener('keydown', (e)=>{ if(e.key==='Escape' && tourActive) tour.end(); });

function startTour(){ tour.start(); }

/* ----------------------------------------------------------
   Journal Selection (Bridge Page)
---------------------------------------------------------- */
function showJournalSelection() {
  const otpCard = $('otpCard');
  if (!otpCard) return;
  
  // Use "Overview" title (always showing this page now)
  const title = _t_safe('JOURNAL_OVERVIEW_TITLE') || 'Overview';
  
  // Helper to format date
  const formatDate = (isoDate) => {
    if (!isoDate) return '';
    try {
      const d = new Date(isoDate);
      return d.toLocaleDateString(window.__BRAND?.lang || 'da-DK', { 
        year: 'numeric', 
        month: 'long', 
        day: 'numeric' 
      });
    } catch(e) {
      return '';
    }
  };
  
  const html = `
    <div style="padding: 30px; max-width: 600px; margin: 0 auto;">
      <h2 style="margin-bottom: 24px; font-size: 24px; font-weight: 600;">${title}</h2>
      <div id="journalList" style="display: flex; flex-direction: column; gap: 12px;">
        ${availableJournals.map(j => {
          // Check if all documents are approved
          const allApproved = j.approvedCount > 0 && j.approvedCount === j.documentCount;
          const borderColor = allApproved ? '#10b981' : '#ddd';
          const bgColor = allApproved ? '#f0fdf4' : 'white';
          
          // Date with label
          const dateLabel = _t_safe('JOURNAL_FIRST_DRAFT_SENT') || 'First draft sent: ';
          const dateStr = j.firstDraftSent 
            ? `<div style="color: #888; font-size: 13px; margin-top: 4px;">${dateLabel}${formatDate(j.firstDraftSent)}</div>` 
            : '';
          
          // All approved badge
          const approvedBadge = allApproved 
            ? `<div style="display: inline-block; padding: 4px 10px; background: #10b981; color: white; border-radius: 12px; font-size: 12px; font-weight: 600; margin-top: 8px;">
                ${_t_safe('JOURNAL_ALL_APPROVED') || '✓ All approved'}
              </div>`
            : '';
          
          // Document type pills with approval indicators
          const docTypes = (j.documentTypes || []).length > 0 
            ? `<ul style="margin: 8px 0 0 0; padding: 0; list-style: none; display: flex; flex-wrap: wrap; gap: 6px;">
                ${j.documentTypes.map(dt => {
                  const stats = (j.documentStatuses || {})[dt] || {total: 0, approved: 0};
                  const isApproved = stats.approved === stats.total && stats.total > 0;
                  const pillBg = isApproved ? '#d1fae5' : '#f0f0f0';
                  const pillColor = isApproved ? '#065f46' : '#555';
                  const checkmark = isApproved ? '✓ ' : '';
                  return `<li style="display: inline-block; padding: 4px 10px; background: ${pillBg}; border-radius: 12px; font-size: 12px; color: ${pillColor}; font-weight: ${isApproved ? '600' : 'normal'};">
                    ${checkmark}📄 ${dt}
                  </li>`;
                }).join('')}
              </ul>`
            : '';
          
          return `
            <button 
              onclick="selectJournal('${j.id}')" 
              style="padding: 20px; background: ${bgColor}; border: 2px solid ${borderColor}; border-radius: 8px; cursor: pointer; text-align: left; transition: all 2:0s; font-family: inherit;"
              onmouseover="this.style.borderColor='var(--accent, #007bff)'; this.style.background='${allApproved ? '#f0fdf4' : '#f8f9fa'}';"
              onmouseout="this.style.borderColor='${borderColor}'; this.style.background='${bgColor}';"
            >
              <div style="font-weight: 600; font-size: 18px; margin-bottom: 6px;">${j.name || j.id}</div>
              ${dateStr}
              ${docTypes}
              ${approvedBadge}
            </button>
          `;
        }).join("")}
      </div>
    </div>
  `;
  
  otpCard.innerHTML = html;
  show(otpCard);
}

async function selectJournal(journalId) {
  selectedJournalId = journalId;
  // Store journal name for brand bar display
  const journal = availableJournals.find(j => j.id === journalId);
  selectedJournalName = journal ? (journal.name || journal.id) : journalId;
  
  spin(true);
  try {
    await fetchDocs(); 
    renderLists(); 
    await loadCurrent();
    enterPortalUI();
    
    // Show back button
    showBackToJournalsButton();
    
    const allOk = docs.every(d=>d.status==='Approved');
    spin(false);
    if(!allOk){ shouldStartTour = true; openIntro(); } else { shouldStartTour = false; }
  } catch(err) {
    spin(false);
    alert(err.message || _t_safe('ERROR_GENERIC'));
  }
}

function showBackToJournalsButton() {
  if (MODE !== 'identifier') return;
  
  const container = $('backToJournalsActions');
  const btn = $('backToJournalsBtn');
  if (!container || !btn) return;
  
  // Re-apply translation for the button when it's shown
  if (btn.dataset.i18n) {
    btn.textContent = _t_safe(btn.dataset.i18n);
  }
  
  // Set up click handler (only once)
  if (!btn.onclick) {
    btn.onclick = () => {
      selectedJournalId = "";
      hide(container);
      
      // Hide portal UI
      hide($('sidebar'));
      hide($('viewerCard'));
      hide($('sidebarActions'));
      hide($('chatFab'));
      
      // Show journal selection again
      showJournalSelection();
    };
  }
  
  // Show the container (which has the sidebar-actions styling)
  container.classList.remove('hidden');
}

// Make globally accessible for onclick handlers
window.selectJournal = selectJournal;

/* ----------------------------------------------------------
   Main flow
---------------------------------------------------------- */
function enterPortalUI(){
  hide($('otpCard'));
  show($('sidebar'));
  show($('viewerCard'));
  show($('sidebarActions'));
  
  // Show menu button now that sidebar is active
  if (menuBtn) menuBtn.style.display = '';
  
  // Chat always visible (will load per-document messages)
  show($('chatFab'));
  if (!hasSeenLabel()){
    const lbl=$('chatLabel');
    if (lbl){ lbl.classList.remove('hidden'); lbl.style.display='block'; setTimeout(positionChatLabel, 0); }
  } else {
    const lbl=$('chatLabel');
    if (lbl){ lbl.classList.add('hidden'); lbl.style.display='none'; }
  }
  
  // Show back button (identifier mode only - always visible now)
  if (MODE === 'identifier') {
    showBackToJournalsButton();
  }
  
  // Display journal name in brand bar (journal mode only)
  const journalNameEl = $('journalName');
  if (journalNameEl) {
    if (MODE === 'journal' && externalId) {
      journalNameEl.textContent = `Journal: ${externalId}`;
      journalNameEl.classList.remove('hidden');
    } else if (MODE === 'identifier' && selectedJournalName) {
      journalNameEl.textContent = `Journal: ${selectedJournalName}`;
      journalNameEl.classList.remove('hidden');
    } else {
      journalNameEl.classList.add('hidden');
    }
  }
}

if ($('otpForm')) $('otpForm').onsubmit = async e=>{
  e.preventDefault(); spin(true); setMsg('');
  try{
    const code = ($('otp')?.value || '').trim();
    if (MODE === 'journal') await verifyOtpJournal(code);
    else                   await verifyOtpIdentifier(code);

    // In identifier mode, always show journal selection (bridge page)
    if (MODE === 'identifier' && !selectedJournalId) {
      spin(false);
      showJournalSelection();
      return;
    }

    await fetchDocs(); renderLists(); await loadCurrent();
    enterPortalUI();

    const allOk = docs.every(d=>d.status==='Approved');
    spin(false);
    if(!allOk){ shouldStartTour = true; openIntro(); } else { shouldStartTour = false; }
    // Note: Periodic chat refresh removed - chat now loads per-document on demand
  }catch(err){ spin(false); setMsg(err.message); }
};

// (Resend button only exists in journal legacy – identifier flow uses requestOtpIdentifier again)
if ($('sendCodeBtn')) $('sendCodeBtn').onclick = async ()=>{
  const btn=$('sendCodeBtn'); if(btn.disabled) return;
  btn.disabled=true;
  try{
    setMsg(_t_safe('OTP_SENDING'));
    await resendOtp();
    setMsg(_t_safe('OTP_SENT'));
  }catch(e){
    setMsg(e.message); btn.disabled=false; btn.textContent=_t_safe('OTP_RESEND_BTN');
  }
};

/* ---------------- Identifier start UI (phone/email + picker) ---------------- */
(function initIdentifierStart(){
  const usePhoneBtn      = $('usePhoneBtn');
  const useEmailBtn      = $('useEmailBtn');
  const idForm           = $('idForm');

  const phoneGroup       = $('phoneGroup');
  const emailGroup       = $('emailGroup');
  const phoneCountryBtn  = $('phoneCountryBtn');
  const phoneDropdown    = $('phoneDropdown');
  const phoneLocal       = $('phoneLocal');
  let   phoneIso         = DEFAULT_PHONE_ISO;

  // Build dropdown
  function setPhoneButton(){
    const cfg = PHONE_COUNTRIES.find(c=>c.iso===phoneIso) || PHONE_COUNTRIES[0];
    phoneCountryBtn.textContent = `${cfg.name} (+${cfg.dial})`;
    phoneCountryBtn.dataset.iso = cfg.iso;
    phoneCountryBtn.dataset.dial = cfg.dial;
  }
  function buildPhoneDropdown(){
    phoneDropdown.innerHTML = '';
    PHONE_COUNTRIES.forEach(c=>{
      const b = document.createElement('button');
      b.type='button';
      b.className='phone-option';
      b.textContent = `${c.name} (+${c.dial})`;
      b.onclick = ()=>{
        phoneIso=c.iso;
        setPhoneButton();
        phoneDropdown.classList.add('hidden');
        // refocus phone input after selection (only if visible later)
        autoFocus('phoneLocal', { delay: 0 });
      };
      phoneDropdown.appendChild(b);
    });
  }
  if (phoneCountryBtn && phoneDropdown){ buildPhoneDropdown(); setPhoneButton(); }
  if (phoneCountryBtn){
    phoneCountryBtn.onclick = (e)=>{ e.preventDefault(); phoneDropdown.classList.toggle('hidden'); };
    document.addEventListener('click', (e)=>{
      if (!phoneDropdown.contains(e.target) && e.target !== phoneCountryBtn) phoneDropdown.classList.add('hidden');
    });
  }

  function setType(t){
    identifierType = t;
    if (usePhoneBtn) usePhoneBtn.classList.toggle('active', t==='phone');
    if (useEmailBtn) useEmailBtn.classList.toggle('active', t==='email');
    if (t==='phone'){ show(phoneGroup); hide(emailGroup); }
    else            { show(emailGroup); hide(phoneGroup); }
    setIdMsg('');
    // Only focus if identifier step is currently visible (avoid stealing focus from OTP/journal screens)
    const idStepVisible = !$('idStep')?.classList.contains('hidden');
    if (idStepVisible){
      if (t==='phone') autoFocus('phoneLocal', { delay: 30 });
      else             autoFocus('emailInput', { delay: 30 });
    }
  }
  if (usePhoneBtn) usePhoneBtn.onclick = ()=> setType('phone');
  if (useEmailBtn) useEmailBtn.onclick = ()=> setType('email');

  if (idForm) idForm.onsubmit = async (e)=>{
    e.preventDefault();
    spin(true);
    try{
      await requestOtpIdentifier();
      setMsg('');
    }catch(err){ setIdMsg(err.message || _t_safe('OTP_RESEND_FAILED')); }
    finally{ spin(false); }
  };

  if (MODE === 'identifier'){ 
    // Check for impersonation token first
    bootImpersonationIfPresent().then(wasImpersonation => {
      // Only show auth step if not impersonation
      if (!wasImpersonation) {
        showStep('auth');
        // Auto-focus the initial input field
        setTimeout(() => {
          if (identifierType === 'phone') autoFocus('phoneLocal', { delay: 0 });
          else                            autoFocus('emailInput', { delay: 0 });
        }, 100);
      }
    });
  } else { 
    showStep('verify'); 
  }
  setType('phone');
  
  // Auto-focus removed from here - now handled in bootImpersonationIfPresent callback
  /*
  setTimeout(() => {
    if (MODE === 'identifier') {
      if (identifierType === 'phone') autoFocus('phoneLocal', { delay: 0 });
      else                            autoFocus('emailInput', { delay: 0 });
    }
  }, 100);
  */

  const so = $('startOverBtn');
  if (so) so.onclick = startOver;
})();

if ($('approveBtn'))    $('approveBtn').onclick   =()=>tryApprove([docs[active].id]);
if ($('approveAllBtn')) $('approveAllBtn').onclick=()=>tryApprove(docs.filter(d=>d.status!=='Approved').map(d=>d.id));

if ($('tourRelaunchBtn')) $('tourRelaunchBtn').onclick = ()=>{ shouldStartTour = false; if(typeof startTour==='function') startTour(); };