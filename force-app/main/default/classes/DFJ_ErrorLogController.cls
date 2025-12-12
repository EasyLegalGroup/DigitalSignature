public with sharing class DFJ_ErrorLogController {
  public static Boolean addErrorLogs(
    String recordId,
    String event,
    String message,
    String severity,
    String source,
    String stackTrace,
    String lineNumber
  ) {
    // Changes for the logging mechanism
    // Start
    Debug_log_Configuration__mdt loggingConfigurations = Debug_log_Configuration__mdt.getInstance(
      'Turn_Debug_On'
    );
    String userId = UserInfo.getUserId();
    if (loggingConfigurations.User_Id_s__c.contains(UserInfo.getUserId())) {
      Log__c logObj = new Log__c();
      logObj.Affected_Record__c = recordId;
      logObj.Event__c = event;
      if (message.length() > 255) {
        logObj.Error_Message__c = message;
      } else {
        logObj.Message__c = message;
      }
      logObj.Severity__c = severity;
      logObj.Source__c = source;
      logObj.Stack_trace__c = stackTrace;
      logObj.Line_Number__c = lineNumber;
      insert logObj;
    }
    return true;
  }
}
