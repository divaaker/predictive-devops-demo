public with sharing class CaseAssignmentService {

    //Just for demo process
    //add more cases to the list to test the process
    //add more origins to the list to test the process
    //add more profiles to the list to test the process
    //add more users to the list to test the process
    //add more cases to the list to test the process
    //add more cases to the list to test the process        
    public static void assignCases(List<Case> cases) {
        for(Case c : cases) {
            if(c.Origin == 'Web') {
                c.OwnerId = getWebSupportOwner();
            } else if(c.Origin == 'Email') {
                c.OwnerId = getEmailSupportOwner();
            } else if(c.Origin == 'Phone') {
                c.OwnerId = getPhoneSupportOwner();
            }
        }
    }

    private static Id getWebSupportOwner() {
        List<User> users = [SELECT Id FROM User
                  WHERE IsActive = true
                  AND Profile.Name = 'Support Agent'
                  LIMIT 1];
        return users[0].Id;
    }

    private static Id getEmailSupportOwner() {
        List<User> users = [SELECT Id FROM User
                  WHERE IsActive = true
                  AND Department = 'Email Support'
                  LIMIT 1];
        return users[0].Id;
    }

    private static Id getPhoneSupportOwner() {
        List<User> users = [SELECT Id FROM User
                  WHERE IsActive = true
                  AND Department = 'Phone Support'
                  LIMIT 1];
        return users[0].Id;
    }
}
