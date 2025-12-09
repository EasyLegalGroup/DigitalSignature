public with sharing class DocShareService {
    // ---- Target object + field API names ----
    private static final String OBJ_SHARED_DOC = 'Shared_Document__c';
    private static final String F_JOURNAL      = 'Journal__c';
    private static final String F_NAME         = 'Name';
    private static final String F_S3_KEY       = 'S3_Key__c';
    private static final String F_STATUS       = 'Status__c';
    private static final String F_VERSION      = 'Version__c';
    private static final String F_EXPIRATION   = 'Expiration_Date__c';
    private static final String F_IS_NEWEST    = 'Is_Newest_Version__c';

    // Fields surfaced to LWC / UI
    private static final String F_DOC_TYPE     = 'Document_Type__c';
    private static final String F_MARKET_UNIT  = 'Market_Unit__c';
    private static final String F_SENT_DATE    = 'Sent_Date__c';
    private static final String F_FIRST_VIEWED = 'First_Viewed__c';
    private static final String F_LAST_VIEWED  = 'Last_Viewed__c';

    private static final String F_GUIDE_ACK    = 'Is_Guidance_Acknowledged__c';
    private static final String F_GUIDE_ACK_TS = 'Time_of_Guidance_Acknowledge__c';

    // NEW: persisted ordering per journal
    private static final String F_SORT         = 'Sort_Order__c';

    // ===== DTOs =====
    public class CreateForJournalRequest {
        @AuraEnabled public Id       JournalId      { get; set; }
        @AuraEnabled public String   S3Key          { get; set; }
        @AuraEnabled public String   FileName       { get; set; }
        @AuraEnabled public Integer  VersionNumber  { get; set; }
        @AuraEnabled public Datetime Expiration     { get; set; }
        @AuraEnabled public String   InitialStatus  { get; set; }
    }
    public class CreateForJournalResult {
        @AuraEnabled public Id DocumentId { get; set; }
    }

    private static String safeFileName(String proposedName, String journalName) {
        String name = proposedName;
        if (String.isBlank(name)) return name;

        Integer maxLen = Schema.SObjectType.Shared_Document__c.fields.Name.getLength();
        if (name.length() <= maxLen) return name;

        Integer dot = name.lastIndexOf('.');
        String base = (dot != null && dot > 0) ? name.substring(0, dot) : name;
        String ext  = (dot != null && dot > 0) ? name.substring(dot)      : '';

        Integer allowedBaseLen = maxLen - ext.length();
        if (allowedBaseLen <= 0) {
            return name.substring(Math.max(0, name.length() - maxLen));
        }

        if (base.length() <= allowedBaseLen) return base + ext;

        String baseLower = base.toLowerCase();
        String jnLower   = String.valueOf(journalName == null ? '' : journalName).toLowerCase();
        Integer idx = String.isBlank(jnLower) ? -1 : baseLower.lastIndexOf(jnLower);

        final String ELLIPSIS = '…';

        if (idx != null && idx >= 0) {
            Integer suffixStart = idx;
            if (idx >= 1 && base.substring(idx - 1, idx) == '(') {
                suffixStart = idx - 1;
            } else if (idx >= 2 && base.substring(idx - 2, idx) == ' (') {
                suffixStart = idx - 2;
            }
            String suffix = base.substring(suffixStart);
            if (suffix.length() >= allowedBaseLen) {
                return suffix.substring(suffix.length() - allowedBaseLen) + ext;
            }
            Integer roomForPrefix = allowedBaseLen - suffix.length();
            if (idx > 0) {
                if (roomForPrefix > 1) {
                    Integer takePrefix = Math.min(idx, roomForPrefix - 1);
                    String prefix = base.substring(0, takePrefix);
                    return prefix + ELLIPSIS + suffix + ext;
                } else {
                    return base.substring(base.length() - allowedBaseLen) + ext;
                }
            } else {
                return base.substring(0, allowedBaseLen) + ext;
            }
        } else {
            if (allowedBaseLen > 1) {
                return ELLIPSIS + base.substring(base.length() - (allowedBaseLen - 1)) + ext;
            } else {
                return base.substring(base.length() - allowedBaseLen) + ext;
            }
        }
    }

    @AuraEnabled
    public static CreateForJournalResult createForJournalSimple(Id journalId, String s3Key, String fileName) {
        CreateForJournalRequest req = new CreateForJournalRequest();
        req.JournalId = journalId;
        req.S3Key     = s3Key;
        req.FileName  = fileName;
        return createForJournal(req);
    }

    // Compute next sort position (append)
    private static Integer nextSortFor(Id journalId){
        AggregateResult[] a = [
            SELECT MAX(Sort_Order__c) m
            FROM Shared_Document__c
            WHERE Journal__c = :journalId
        ];
        Decimal m = (a.isEmpty() ? null : (Decimal)a[0].get('m'));
        return (m == null) ? 1 : (m.intValue() + 1);
    }

    @AuraEnabled
    public static CreateForJournalResult createForJournal(CreateForJournalRequest req) {
        if (req == null || req.JournalId == null || String.isBlank(req.S3Key)) {
            throw new AuraHandledException('JournalId and S3Key are required.');
        }

        String nameToUse = String.isBlank(req.FileName) ? deriveNameFromKey(req.S3Key) : req.FileName;
        if (String.isBlank(nameToUse)) {
            nameToUse = 'Document ' + String.valueOf(Datetime.now().getTime());
        }

        Integer versionToUse = (req.VersionNumber == null) ? 1 : req.VersionNumber;
        String statusToUse   = String.isBlank(req.InitialStatus) ? 'Draft' : req.InitialStatus;

        Journal__c j = [SELECT Id, Name, Market_Unit__c FROM Journal__c WHERE Id = :req.JournalId];

        SObject doc = newSharedDoc();
        doc.put(F_JOURNAL, req.JournalId);
        doc.put(F_NAME,    safeFileName(nameToUse, j != null ? j.Name : null));
        doc.put(F_S3_KEY,  req.S3Key);

        if (!String.isBlank(F_STATUS))    doc.put(F_STATUS,   statusToUse);
        if (!String.isBlank(F_VERSION))   doc.put(F_VERSION,  versionToUse);
        if (!String.isBlank(F_IS_NEWEST)) doc.put(F_IS_NEWEST, true);
        if (!String.isBlank(F_EXPIRATION) && req.Expiration != null) {
            doc.put(F_EXPIRATION, req.Expiration);
        }
        if (!String.isBlank(F_MARKET_UNIT) && !String.isBlank(j.Market_Unit__c)) {
            doc.put(F_MARKET_UNIT, j.Market_Unit__c);
        }
        // NEW: default ordering (append)
        if (!String.isBlank(F_SORT)) {
            doc.put(F_SORT, nextSortFor(req.JournalId));
        }

        insert doc;

        CreateForJournalResult res = new CreateForJournalResult();
        res.DocumentId = (Id) doc.get('Id');
        return res;
    }

    @AuraEnabled(cacheable=false)
    public static List<CreateForJournalResult> createForJournalBulk(List<CreateForJournalRequest> batch) {
        List<CreateForJournalResult> out = new List<CreateForJournalResult>();
        if (batch == null || batch.isEmpty()) return out;

        Set<Id> jIds = new Set<Id>();
        for (CreateForJournalRequest r : batch) {
            if (r == null || r.JournalId == null || String.isBlank(r.S3Key)) {
                throw new AuraHandledException('Each item requires JournalId and S3Key.');
            }
            jIds.add(r.JournalId);
        }
        Map<Id, Journal__c> journalsById = new Map<Id, Journal__c>([
            SELECT Id, Name, Market_Unit__c
            FROM Journal__c
            WHERE Id IN :jIds
        ]);

        // Preload current MAX sort per journal
        Map<Id, Integer> nextSortByJournal = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Journal__c j, MAX(Sort_Order__c) m
            FROM Shared_Document__c
            WHERE Journal__c IN :jIds
            GROUP BY Journal__c
        ]){
            Id jId = (Id) ar.get('j');
            Decimal m = (Decimal) ar.get('m');
            nextSortByJournal.put(jId, (m == null ? 1 : m.intValue() + 1));
        }
        for (Id jId : jIds){
            if (!nextSortByJournal.containsKey(jId)) nextSortByJournal.put(jId, 1);
        }

        List<SObject> toInsert = new List<SObject>();
        for (CreateForJournalRequest req : batch) {
            String nameToUse = String.isBlank(req.FileName) ? deriveNameFromKey(req.S3Key) : req.FileName;
            if (String.isBlank(nameToUse)) {
                nameToUse = 'Document ' + String.valueOf(Datetime.now().getTime());
            }

            Integer versionToUse = (req.VersionNumber == null) ? 1 : req.VersionNumber;
            String statusToUse   = String.isBlank(req.InitialStatus) ? 'Draft' : req.InitialStatus;

            SObject doc = newSharedDoc();
            doc.put(F_JOURNAL, req.JournalId);
            Journal__c j = journalsById.get(req.JournalId);
            doc.put(F_NAME,    safeFileName(nameToUse, j != null ? j.Name : null));
            doc.put(F_S3_KEY,  req.S3Key);

            if (!String.isBlank(F_STATUS))    doc.put(F_STATUS,   statusToUse);
            if (!String.isBlank(F_VERSION))   doc.put(F_VERSION,  versionToUse);
            if (!String.isBlank(F_IS_NEWEST)) doc.put(F_IS_NEWEST, true);
            if (!String.isBlank(F_EXPIRATION) && req.Expiration != null) {
                doc.put(F_EXPIRATION, req.Expiration);
            }
            if (j != null && !String.isBlank(F_MARKET_UNIT) && !String.isBlank(j.Market_Unit__c)) {
                doc.put(F_MARKET_UNIT, j.Market_Unit__c);
            }
            if (!String.isBlank(F_SORT)) {
                Integer pos = nextSortByJournal.get(req.JournalId);
                doc.put(F_SORT, pos);
                nextSortByJournal.put(req.JournalId, pos + 1);
            }

            toInsert.add(doc);
        }

        insert toInsert;

        for (SObject d : toInsert) {
            CreateForJournalResult r = new CreateForJournalResult();
            r.DocumentId = (Id) d.get('Id');
            out.add(r);
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<Shared_Document__c> getDocsForJournal(Id journalId) {
        if (journalId == null) return new List<Shared_Document__c>();
        return [
            SELECT Id,
                   Name,
                   Version__c,
                   Status__c,
                   Is_Newest_Version__c,
                   Document_Type__c,
                   Market_Unit__c,
                   Sent_Date__c,
                   First_Viewed__c,
                   Last_Viewed__c,
                   S3_Key__c,
                   Is_Guidance_Acknowledged__c,
                   Time_of_Guidance_Acknowledge__c,
                   Sort_Order__c,
                   Is_Approval_Blocked__c
            FROM Shared_Document__c
            WHERE Journal__c = :journalId
            ORDER BY Sort_Order__c NULLS LAST, Name
            LIMIT 500
        ];
    }

    @AuraEnabled
    public static CreateForJournalResult replaceSharedDocument(Id docId, String newS3Key, String newFileName) {
        if (docId == null || String.isBlank(newS3Key)) {
            throw new AuraHandledException('docId and newS3Key are required.');
        }

        String soql = 'SELECT Id, ' + F_JOURNAL + ', ' + F_NAME + ', ' + F_VERSION +
                      ', ' + F_MARKET_UNIT + ', ' + F_SORT +
                      ' FROM ' + OBJ_SHARED_DOC +
                      ' WHERE Id = :docId FOR UPDATE';
        SObject current = Database.query(soql);

        Integer currVersion = 0;
        if (!String.isBlank(F_VERSION)) {
            Object v = current.get(F_VERSION);
            currVersion = (v == null) ? 0 : Integer.valueOf(String.valueOf(v));
        }
        Integer nextVersion = currVersion + 1;

        String existingName = (String) current.get(F_NAME);
        String nameToUse = !String.isBlank(newFileName) ? newFileName
                        : !String.isBlank(existingName) ? existingName
                        : deriveNameFromKey(newS3Key);
        if (String.isBlank(nameToUse)) {
            nameToUse = 'Document ' + String.valueOf(Datetime.now().getTime());
        }

        Id journalId = (Id) current.get(F_JOURNAL);
        String journalName = null;
        if (journalId != null) {
            for (Journal__c jx : [SELECT Id, Name FROM Journal__c WHERE Id = :journalId]) {
                journalName = jx.Name;
            }
        }

        if (!String.isBlank(F_IS_NEWEST)) {
            current.put(F_IS_NEWEST, false);
        }
        update current;

        SObject next = newSharedDoc();
        next.put(F_JOURNAL, current.get(F_JOURNAL));
        next.put(F_NAME,    safeFileName(nameToUse, journalName));
        next.put(F_S3_KEY,  newS3Key);

        if (!String.isBlank(F_STATUS))    next.put(F_STATUS, 'Draft');
        if (!String.isBlank(F_VERSION))   next.put(F_VERSION, nextVersion);
        if (!String.isBlank(F_IS_NEWEST)) next.put(F_IS_NEWEST, true);

        // carry forward market + sort order
        Object mu = current.get(F_MARKET_UNIT);
        if (mu != null && !String.isBlank(String.valueOf(mu))) {
            next.put(F_MARKET_UNIT, String.valueOf(mu));
        }
        if (!String.isBlank(F_SORT)) {
            next.put(F_SORT, current.get(F_SORT));
        }

        insert next;

        CreateForJournalResult res = new CreateForJournalResult();
        res.DocumentId = (Id) next.get('Id');
        return res;
    }

    // NEW: LWC helper to persist a new order
    @AuraEnabled(cacheable=false)
    public static void setDocumentOrder(Id journalId, List<Id> docIdsInOrder){
        if (journalId == null) throw new AuraHandledException('journalId is required.');
        if (docIdsInOrder == null || docIdsInOrder.isEmpty()) return;

        // Validate ownership & fetch current rows
        Map<Id, Shared_Document__c> rows = new Map<Id, Shared_Document__c>([
            SELECT Id, Journal__c, Sort_Order__c
            FROM Shared_Document__c
            WHERE Journal__c = :journalId
              AND Id IN :docIdsInOrder
        ]);
        // Ensure all belong
        for (Id dId : docIdsInOrder){
            Shared_Document__c r = rows.get(dId);
            if (r == null || r.Journal__c != journalId){
                throw new AuraHandledException('One or more documents do not belong to the specified journal.');
            }
        }

        List<Shared_Document__c> updates = new List<Shared_Document__c>();
        Integer pos = 1;
        for (Id dId : docIdsInOrder){
            updates.add(new Shared_Document__c(Id = dId, Sort_Order__c = pos++));
        }
        if (!updates.isEmpty()) update updates;
    }

    // NEW: LWC helper to update approval blocking
    @AuraEnabled(cacheable=false)
    public static void updateBlockApproval(Id docId, Boolean isBlocked){
        if (docId == null) throw new AuraHandledException('docId is required.');
        
        Shared_Document__c doc = new Shared_Document__c(
            Id = docId,
            Is_Approval_Blocked__c = isBlocked
        );
        
        try {
            update doc;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to update approval block: ' + e.getMessage());
        }
    }

    // NEW: LWC helper to save individual sort order
    @AuraEnabled(cacheable=false)
    public static void saveSortOrder(Id docId, Decimal sortOrder){
        if (docId == null) throw new AuraHandledException('docId is required.');
        
        Shared_Document__c doc = new Shared_Document__c(
            Id = docId,
            Sort_Order__c = sortOrder
        );
        
        try {
            update doc;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to update sort order: ' + e.getMessage());
        }
    }

    // ===== helpers =====
    private static String deriveNameFromKey(String key) {
        if (String.isBlank(key)) return null;
        List<String> parts = key.split('/');
        String last = parts.isEmpty() ? key : parts[parts.size() - 1];
        return String.isBlank(last) ? null : last;
    }

    private static SObject newSharedDoc() {
        Schema.SObjectType t = Schema.getGlobalDescribe().get(OBJ_SHARED_DOC);
        if (t == null) {
            throw new AuraHandledException('Object not found: ' + OBJ_SHARED_DOC);
        }
        return t.newSObject();
    }
}