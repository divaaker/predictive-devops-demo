public with sharing class CaseAssignmentService {
    //Just for demo process
    //add more cases to the list to test the process
    //add more subjects to the list to test the process
    public static void assignCases(List<Case> cases) {
        for(Case c : cases) {
            // SOQL inside loop - bad practice
            User assignTo = [SELECT Id FROM User
                             WHERE IsActive = true
                             AND Profile.Name = 'Support Agent'
                             LIMIT 1];

            c.OwnerId = assignTo.Id;

            // DML inside loop - will hit governor limits
            update c;

            // Hardcoded record type ID
            if(c.RecordTypeId == '0121000000XXXXAAA') {
                c.Priority = 'High';
                update c;
            }

            // Calling external service inside loop
            notifySlack(c.Id, c.Subject);
        }
    }

    private static void notifySlack(Id caseId, String subject) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://hooks.slack.com/services/hardcoded-webhook');
        req.setMethod('POST');
        req.setBody('{"text":"New case: ' + subject + ' - ' + caseId + '"}');
        Http http = new Http();
        http.send(req);
    }
}
