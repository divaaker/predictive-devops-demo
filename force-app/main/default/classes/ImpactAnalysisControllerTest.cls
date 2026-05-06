@isTest
private class ImpactAnalysisControllerTest {
    private class ToolingDependencyMock implements HttpCalloutMock {
        private final String SAMPLE_CLASS_ID = '01p570000099dKXBAY';
        private final String SAMPLE_CLASS_NAME = 'ImpactSample';
        private final String OTHER_COMPONENT_ID = '01p570000099dKXCAY';
        private final String OTHER_COMPONENT_NAME = 'ImpactConsumer';

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            String soql = decodeSoql(req);
            if (soql.toLowerCase().contains('from metadatacomponentdependency')) {
                if (soql.contains(SAMPLE_CLASS_ID)) {
                    String depBody =
                        toolingWrap(
                            '[' +
                                singleDependencyRow(
                                    OTHER_COMPONENT_ID,
                                    OTHER_COMPONENT_NAME,
                                    'ApexClass',
                                    SAMPLE_CLASS_ID,
                                    SAMPLE_CLASS_NAME,
                                    'ApexClass'
                                ) +
                                ']'
                        );
                    res.setBody(depBody);
                    return res;
                }
                res.setBody(emptyToolingEnvelope());
                return res;
            }

            if (soql.toLowerCase().contains('from apexclass')) {
                if (soql.toLowerCase().contains('like')) {
                    String body =
                        toolingWrap(
                            '[' +
                                apexClassRecord(SAMPLE_CLASS_ID, SAMPLE_CLASS_NAME) +
                                ']'
                        );
                    res.setBody(body);
                    return res;
                }
                if (soql.contains(SAMPLE_CLASS_ID)) {
                    String body =
                        toolingWrap(
                            '[' + apexClassRecord(SAMPLE_CLASS_ID, SAMPLE_CLASS_NAME) + ']'
                        );
                    res.setBody(body);
                    return res;
                }
                res.setBody(emptyToolingEnvelope());
                return res;
            }

            res.setBody(emptyToolingEnvelope());
            return res;
        }

        private String apexClassRecord(String apexId, String name) {
            return '{' +
                '"attributes":{"type":"ApexClass"},' +
                '"Id":"' +
                apexId +
                '",' +
                '"Name":"' +
                name +
                '"' +
                '}';
        }

        private String singleDependencyRow(
            String metaId,
            String metaName,
            String metaType,
            String refId,
            String refName,
            String refType
        ) {
            return '{' +
                '"attributes":{"type":"MetadataComponentDependency"},' +
                '"MetadataComponentId":"' +
                metaId +
                '",' +
                '"MetadataComponentName":"' +
                metaName +
                '",' +
                '"MetadataComponentType":"' +
                metaType +
                '",' +
                '"RefMetadataComponentId":"' +
                refId +
                '",' +
                '"RefMetadataComponentName":"' +
                refName +
                '",' +
                '"RefMetadataComponentType":"' +
                refType +
                '"' +
                '}';
        }

        private String toolingWrap(String recordsJson) {
            return '{"totalSize":1,"done":true,"records":' + recordsJson + '}';
        }

        private String emptyToolingEnvelope() {
            return '{"totalSize":0,"done":true,"records":[]}';
        }

        private String decodeSoql(HttpRequest req) {
            String endpoint = req.getEndpoint();
            if (String.isBlank(endpoint)) {
                return '';
            }
            Integer marker = endpoint.toLowerCase().indexOf('/tooling/query?q=');
            if (marker < 0) {
                marker = endpoint.toLowerCase().indexOf('?q=');
            }
            if (marker < 0) {
                return '';
            }
            Integer queryStart = endpoint.indexOf('q=', marker);
            if (queryStart < 0) {
                return '';
            }
            queryStart += 2;
            Integer ampersand = endpoint.indexOf('&', queryStart);
            String rawSegment = ampersand > queryStart ? endpoint.substring(queryStart, ampersand) : endpoint.substring(queryStart);

            rawSegment = rawSegment.replace('+', ' ');
            return EncodingUtil.urlDecode(rawSegment, 'UTF-8');
        }
    }

    @isTest
    static void search_and_graph_handles_tooling_dependency() {
        Test.setMock(HttpCalloutMock.class, new ToolingDependencyMock());

        Test.startTest();
        List<ImpactAnalysisController.MetadataSearchHit> hits = ImpactAnalysisController.searchMetadataComponents(
            'Impact',
            15
        );
        System.assert(!hits.isEmpty(), 'Stub should produce at least one class hit.');
        ImpactAnalysisController.GraphPayload graph = ImpactAnalysisController.getDependencyGraph(
            hits[0].id,
            'DOWNSTREAM',
            200,
            40
        );
        Test.stopTest();

        System.assertEquals(null, graph.errorMessage, graph.errorMessage);
        System.assert(graph.nodes.size() > 1, 'Graph should capture both referencing components.');
        System.assert(graph.edges.size() > 0, 'Graph should expose at least one dependency edge.');
    }

    @isTest
    static void blank_terms_return_emptyHits() {
        System.assertEquals(0, ImpactAnalysisController.searchMetadataComponents('', 10).size());
        System.assertEquals(0, ImpactAnalysisController.searchMetadataComponents(' "%" ', 10).size());
    }

    @isTest
    static void invalid_root_returns_payload_error() {
        Test.setMock(HttpCalloutMock.class, new ToolingDependencyMock());

        ImpactAnalysisController.GraphPayload graph = ImpactAnalysisController.getDependencyGraph(
            '01p000099999998AAA',
            'DOWNSTREAM',
            50,
            10
        );
        System.assertNotEquals(null, graph.errorMessage);
    }
}
