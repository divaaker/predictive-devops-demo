public with sharing class ToolingApiClient {
    private static final String API_VERSION = 'v59.0';

    public class ToolingException extends Exception {}

    /**
     * Executes a read-only Tooling SOQL query. Requires Remote Site Setting for Url.getOrgDomainUrl().
     */
    public static List<Map<String, Object>> query(String soql) {
        String base = Url.getOrgDomainUrl().toExternalForm();
        String endpoint =
            base +
            '/services/data/' +
            API_VERSION +
            '/tooling/query?q=' +
            EncodingUtil.urlEncode(soql, 'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Content-Type', 'application/json');

        Http http = new Http();
        HttpResponse res = http.send(req);
        if (res.getStatusCode() >= 400) {
            throw new ToolingException(
                'Tooling API ' +
                    res.getStatusCode() +
                    ': ' +
                    abbreviate(res.getBody(), 4000)
            );
        }

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Object recs = body.get('records');
        if (recs instanceof List<Object>) {
            List<Map<String, Object>> out = new List<Map<String, Object>>();
            for (Object row : (List<Object>) recs) {
                if (row instanceof Map<String, Object>) {
                    out.add((Map<String, Object>) row);
                }
            }
            return out;
        }
        return new List<Map<String, Object>>();
    }

    private static String abbreviate(String s, Integer maxLen) {
        if (s == null) {
            return '';
        }
        if (s.length() <= maxLen) {
            return s;
        }
        return s.substring(0, maxLen) + '…';
    }
}
