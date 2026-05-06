public with sharing class ImpactAnalysisController {
    private static final Integer DEFAULT_MAX_NODES = 200;
    private static final Integer DEFAULT_MAX_ITERATIONS = 40;
    private static final Integer IN_CHUNK = 80;

    public class MetadataSearchHit {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String type;
    }

    public class GraphNodeDto {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String type;
        @AuraEnabled
        public Boolean isRoot;
    }

    public class GraphEdgeDto {
        @AuraEnabled
        public String fromId;
        @AuraEnabled
        public String toId;
    }

    public class GraphPayload {
        @AuraEnabled
        public List<GraphNodeDto> nodes;
        @AuraEnabled
        public List<GraphEdgeDto> edges;
        @AuraEnabled
        public String infoMessage;
        @AuraEnabled
        public String errorMessage;
    }

    /**
     * Text search across a few Tooling entities (classes, triggers, LWCs, flows).
     */
    @AuraEnabled
    public static List<MetadataSearchHit> searchMetadataComponents(String searchTerm, Integer rowLimit) {
        List<MetadataSearchHit> hits = new List<MetadataSearchHit>();
        if (String.isBlank(searchTerm)) {
            return hits;
        }

        String cleanedToken = sanitizeLikeToken(searchTerm.trim());
        if (String.isBlank(cleanedToken) || cleanedToken.length() < 2) {
            return hits;
        }

        Integer limitEach = rowLimit == null || rowLimit < 1 ? 15 : Math.min(rowLimit, 25);
        String likeArg = '%' + cleanedToken + '%';

        hits.addAll(queryApexClasses(likeArg, limitEach));
        hits.addAll(queryApexTriggers(likeArg, limitEach));
        hits.addAll(queryLightningBundles(likeArg, limitEach));
        hits.addAll(queryFlowDefinitions(likeArg, limitEach));

        return hits;
    }

    /**
     * direction: DOWNSTREAM = what depends on root (impact if root changes).
     *            UPSTREAM   = what root depends on (dependencies of root).
     */
    @AuraEnabled
    public static GraphPayload getDependencyGraph(
        String rootId,
        String direction,
        Integer maxNodes,
        Integer maxIterations
    ) {
        GraphPayload payload = new GraphPayload();
        payload.nodes = new List<GraphNodeDto>();
        payload.edges = new List<GraphEdgeDto>();
        payload.infoMessage = '';

        if (String.isBlank(rootId)) {
            payload.errorMessage = 'Select a metadata row first.';
            return payload;
        }

        Boolean downstream =
            direction == null || direction.equalsIgnoreCase('DOWNSTREAM');
        Integer nodeCap = maxNodes == null ? DEFAULT_MAX_NODES : Math.min(Math.max(maxNodes, 1), 200);
        Integer iterCap = maxIterations == null
            ? DEFAULT_MAX_ITERATIONS
            : Math.min(Math.max(maxIterations, 1), 100);

        try {
            RootInfo root = resolveRoot(rootId.trim());
            if (root == null) {
                payload.errorMessage = 'Unknown or unsupported metadata id.';
                return payload;
            }

            buildGraph(payload, root, downstream, nodeCap, iterCap);
            payload.infoMessage =
                'Showing up to ' +
                nodeCap +
                ' nodes using MetadataComponentDependency (Tooling). Deeper chains may stop early due to governor limits.';
        } catch (Exception e) {
            payload.errorMessage = buildUserFacingError(e);
        }

        return payload;
    }

    private static String buildUserFacingError(Exception e) {
        String msg = e.getMessage();
        if (e.getTypeName() == 'System.CalloutException' && msg != null && msg.contains('Unauthorized endpoint')) {
            return 'Callout blocked. In Setup → Remote Site Settings, allow your org API domain returned by Url.getOrgDomainUrl() (same as Company Information / My Domain), then retry.';
        }
        return String.isBlank(msg) ? 'Unexpected error.' : msg;
    }

    private class RootInfo {
        String id;
        String name;
        String type;
        RootInfo(String id, String name, String type) {
            this.id = id;
            this.name = name;
            this.type = type;
        }
    }

    private static RootInfo resolveRoot(String rootId) {
        RootInfo bySelect = resolveByDirectSelect(rootId);
        if (bySelect != null) {
            return bySelect;
        }
        return resolveByDependencyLookup(rootId);
    }

    private static RootInfo resolveByDirectSelect(String rootId) {
        List<String> attempts = new List<String>{
            'SELECT Id, Name FROM ApexClass WHERE Id = \'' +
            String.escapeSingleQuotes(rootId) +
            '\' LIMIT 1',
            'SELECT Id, Name FROM ApexTrigger WHERE Id = \'' +
            String.escapeSingleQuotes(rootId) +
            '\' LIMIT 1',
            'SELECT Id, DeveloperName FROM LightningComponentBundle WHERE Id = \'' +
            String.escapeSingleQuotes(rootId) +
            '\' LIMIT 1',
            'SELECT Id, DeveloperName FROM FlowDefinition WHERE Id = \'' +
            String.escapeSingleQuotes(rootId) +
            '\' LIMIT 1'
        };

        for (String soql : attempts) {
            try {
                List<Map<String, Object>> rows = ToolingApiClient.query(soql);
                if (rows.isEmpty()) {
                    continue;
                }
                Map<String, Object> row = rows[0];
                String id = stringVal(row.get('Id'));
                if (soql.contains('ApexClass')) {
                    return new RootInfo(id, stringVal(row.get('Name')), 'ApexClass');
                }
                if (soql.contains('ApexTrigger')) {
                    return new RootInfo(id, stringVal(row.get('Name')), 'ApexTrigger');
                }
                if (soql.contains('LightningComponentBundle')) {
                    return new RootInfo(id, stringVal(row.get('DeveloperName')), 'LightningComponentBundle');
                }
                if (soql.contains('FlowDefinition')) {
                    return new RootInfo(id, stringVal(row.get('DeveloperName')), 'FlowDefinition');
                }
            } catch (Exception e) {
                /* try next */
            }
        }
        return null;
    }

    private static RootInfo resolveByDependencyLookup(String rootId) {
        String soql =
            'SELECT MetadataComponentId, MetadataComponentName, MetadataComponentType, ' +
            'RefMetadataComponentId, RefMetadataComponentName, RefMetadataComponentType ' +
            'FROM MetadataComponentDependency WHERE MetadataComponentId = \'' +
            String.escapeSingleQuotes(rootId) +
            '\' OR RefMetadataComponentId = \'' +
            String.escapeSingleQuotes(rootId) +
            '\' LIMIT 1';
        try {
            List<Map<String, Object>> rows = ToolingApiClient.query(soql);
            if (rows.isEmpty()) {
                return null;
            }
            Map<String, Object> row = rows[0];
            String metaId = stringVal(row.get('MetadataComponentId'));
            if (metaId.equals(rootId)) {
                return new RootInfo(
                    metaId,
                    stringVal(row.get('MetadataComponentName')),
                    stringVal(row.get('MetadataComponentType'))
                );
            }
            String refId = stringVal(row.get('RefMetadataComponentId'));
            if (refId.equals(rootId)) {
                return new RootInfo(
                    refId,
                    stringVal(row.get('RefMetadataComponentName')),
                    stringVal(row.get('RefMetadataComponentType'))
                );
            }
        } catch (Exception e) {
            return null;
        }
        return null;
    }

    private static void buildGraph(
        GraphPayload payload,
        RootInfo root,
        Boolean downstream,
        Integer nodeCap,
        Integer iterCap
    ) {
        Map<String, GraphNodeDto> nodes = new Map<String, GraphNodeDto>();
        Set<String> edgeKeys = new Set<String>();
        List<GraphEdgeDto> edges = new List<GraphEdgeDto>();

        GraphNodeDto rootNode = new GraphNodeDto();
        rootNode.id = root.id;
        rootNode.name = root.name;
        rootNode.type = root.type;
        rootNode.isRoot = true;
        nodes.put(root.id, rootNode);

        Set<String> frontier = new Set<String>{ root.id };
        Set<String> expandedSeeds = new Set<String>();
        Integer iterations = 0;

        while (!frontier.isEmpty() && nodes.size() < nodeCap && iterations < iterCap) {
            iterations++;
            expandedSeeds.addAll(frontier);
            Set<String> nextFrontier = new Set<String>();
            List<String> batch = new List<String>(frontier);

            for (Integer i = 0; i < batch.size(); i += IN_CHUNK) {
                Integer chunkEnd = Math.min(i + IN_CHUNK, batch.size());
                List<String> chunk = new List<String>();
                for (Integer j = i; j < chunkEnd; j++) {
                    chunk.add(batch[j]);
                }

                String inList = quoteIdList(chunk);
                String soql;
                if (downstream) {
                    soql =
                        'SELECT MetadataComponentId, MetadataComponentName, MetadataComponentType, ' +
                        'RefMetadataComponentId, RefMetadataComponentName, RefMetadataComponentType ' +
                        'FROM MetadataComponentDependency WHERE RefMetadataComponentId IN (' +
                        inList +
                        ') LIMIT 2000';
                } else {
                    soql =
                        'SELECT MetadataComponentId, MetadataComponentName, MetadataComponentType, ' +
                        'RefMetadataComponentId, RefMetadataComponentName, RefMetadataComponentType ' +
                        'FROM MetadataComponentDependency WHERE MetadataComponentId IN (' +
                        inList +
                        ') LIMIT 2000';
                }

                List<Map<String, Object>> rows = ToolingApiClient.query(soql);
                for (Map<String, Object> row : rows) {
                    if (nodes.size() >= nodeCap) {
                        break;
                    }

                    String depId = normalizeId(row.get('MetadataComponentId'));
                    String depName = coalesceName(stringVal(row.get('MetadataComponentName')), depId);
                    String depType = stringVal(row.get('MetadataComponentType'));

                    String refId = normalizeId(row.get('RefMetadataComponentId'));
                    String refName = coalesceName(stringVal(row.get('RefMetadataComponentName')), refId);
                    String refType = stringVal(row.get('RefMetadataComponentType'));

                    if (String.isBlank(depId) || String.isBlank(refId) || depId.equals(refId)) {
                        continue;
                    }

                    if (nodes.size() >= nodeCap) {
                        break;
                    }
                    tryAddNode(nodes, depId, depName, depType, nodeCap);
                    if (nodes.size() >= nodeCap) {
                        break;
                    }
                    tryAddNode(nodes, refId, refName, refType, nodeCap);

                    GraphEdgeDto edge = new GraphEdgeDto();
                    if (downstream) {
                        edge.fromId = refId;
                        edge.toId = depId;
                    } else {
                        edge.fromId = depId;
                        edge.toId = refId;
                    }
                    String ek = edge.fromId + '>' + edge.toId;
                    if (!edgeKeys.contains(ek)) {
                        edgeKeys.add(ek);
                        edges.add(edge);
                    }

                    if (downstream) {
                        if (!expandedSeeds.contains(depId)) {
                            nextFrontier.add(depId);
                        }
                    } else {
                        if (!expandedSeeds.contains(refId)) {
                            nextFrontier.add(refId);
                        }
                    }
                }
            }

            frontier = nextFrontier;
        }

        payload.nodes = new List<GraphNodeDto>(nodes.values());
        payload.edges = edges;
    }

    private static void tryAddNode(
        Map<String, GraphNodeDto> nodes,
        String id,
        String name,
        String typeKey,
        Integer nodeCap
    ) {
        if (nodes.containsKey(id)) {
            return;
        }
        if (nodes.size() >= nodeCap) {
            return;
        }
        GraphNodeDto n = new GraphNodeDto();
        n.id = id;
        n.name = name;
        n.type = typeKey;
        n.isRoot = false;
        nodes.put(id, n);
    }

    private static List<MetadataSearchHit> queryApexClasses(String likeArg, Integer limitEach) {
        String soql =
            'SELECT Id, Name FROM ApexClass WHERE Name LIKE \'' +
            String.escapeSingleQuotes(likeArg) +
            '\' ORDER BY Name LIMIT ' +
            String.valueOf(limitEach);
        return mapToolingRows(ToolingApiClient.query(soql), 'ApexClass', 'Id', 'Name');
    }

    private static List<MetadataSearchHit> queryApexTriggers(String likeArg, Integer limitEach) {
        String soql =
            'SELECT Id, Name FROM ApexTrigger WHERE Name LIKE \'' +
            String.escapeSingleQuotes(likeArg) +
            '\' ORDER BY Name LIMIT ' +
            String.valueOf(limitEach);
        return mapToolingRows(ToolingApiClient.query(soql), 'ApexTrigger', 'Id', 'Name');
    }

    private static List<MetadataSearchHit> queryLightningBundles(String likeArg, Integer limitEach) {
        String soql =
            'SELECT Id, DeveloperName FROM LightningComponentBundle WHERE DeveloperName LIKE \'' +
            String.escapeSingleQuotes(likeArg) +
            '\' ORDER BY DeveloperName LIMIT ' +
            String.valueOf(limitEach);
        return mapToolingRows(
            ToolingApiClient.query(soql),
            'LightningComponentBundle',
            'Id',
            'DeveloperName'
        );
    }

    private static List<MetadataSearchHit> queryFlowDefinitions(String likeArg, Integer limitEach) {
        String soql =
            'SELECT Id, DeveloperName FROM FlowDefinition WHERE DeveloperName LIKE \'' +
            String.escapeSingleQuotes(likeArg) +
            '\' ORDER BY DeveloperName LIMIT ' +
            String.valueOf(limitEach);
        return mapToolingRows(ToolingApiClient.query(soql), 'FlowDefinition', 'Id', 'DeveloperName');
    }

    private static List<MetadataSearchHit> mapToolingRows(
        List<Map<String, Object>> rows,
        String type,
        String idField,
        String nameField
    ) {
        List<MetadataSearchHit> hits = new List<MetadataSearchHit>();
        for (Map<String, Object> row : rows) {
            MetadataSearchHit h = new MetadataSearchHit();
            h.id = stringVal(row.get(idField));
            h.name = stringVal(row.get(nameField));
            h.type = type;
            hits.add(h);
        }
        return hits;
    }

    /** Strips LIKE metacharacters so user input stays a plain substring token. */
    private static String sanitizeLikeToken(String s) {
        if (s == null) {
            return '';
        }
        return s.replace('%', '').replace('_', '').replace('\\', '');
    }

    private static String stringVal(Object o) {
        return o == null ? '' : String.valueOf(o);
    }

    private static String normalizeId(Object o) {
        String v = stringVal(o);
        if (String.isBlank(v) || v == 'null') {
            return '';
        }
        return v;
    }

    private static String coalesceName(String name, String id) {
        return String.isBlank(name) ? id : name;
    }

    private static String quoteIdList(List<String> ids) {
        List<String> parts = new List<String>();
        for (String id : ids) {
            parts.add('\'' + String.escapeSingleQuotes(id) + '\'');
        }
        return String.join(parts, ',');
    }
}
