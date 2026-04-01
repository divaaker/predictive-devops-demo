public with sharing class CaseAssignmentService {
    //do not use this in production
    //this is bad deployment process
    public static void assignCases(List<Case> cases) {
        Set<Id> caseIds = new Set<Id>();
        for(Case c : cases) {
            caseIds.add(c.Id);
        }
        List<User> agents = [SELECT Id FROM User
                             WHERE IsActive = true
                             AND Profile.Name = 'Support Agent'
                             ORDER BY LastModifiedDate DESC
                             LIMIT 1];
        if(agents.isEmpty()) return;
        for(Case c : cases) {
            c.OwnerId = agents[0].Id;
        }
        update cases;
    }
}
