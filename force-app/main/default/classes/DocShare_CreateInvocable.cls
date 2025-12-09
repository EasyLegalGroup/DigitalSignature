public with sharing class DocShare_CreateInvocable {
    public class Request {
        @InvocableVariable(required=true) public Id JournalId;
        @InvocableVariable(required=true) public String S3Key;
        @InvocableVariable public String  FileName;
        @InvocableVariable public Integer VersionNumber;
        @InvocableVariable public Datetime Expiration;
        @InvocableVariable public String  InitialStatus;
    }
    public class Result {
        @InvocableVariable public Id DocumentId;
    }

    @InvocableMethod(label='Create Shared Document for Journal')
    public static List<Result> run(List<Request> batch) {
        List<Result> out = new List<Result>();
        if (batch == null) return out;

        for (Request r : batch) {
            DocShareService.CreateForJournalRequest req = new DocShareService.CreateForJournalRequest();
            req.JournalId     = r.JournalId;
            req.S3Key         = r.S3Key;
            req.FileName      = r.FileName;
            req.VersionNumber = r.VersionNumber;
            req.Expiration    = r.Expiration;
            req.InitialStatus = r.InitialStatus;

            DocShareService.CreateForJournalResult svc = DocShareService.createForJournal(req);

            Result res = new Result();
            res.DocumentId = svc.DocumentId;
            out.add(res);
        }
        return out;
    }
}