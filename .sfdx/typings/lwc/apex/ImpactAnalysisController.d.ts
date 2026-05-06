declare module "@salesforce/apex/ImpactAnalysisController.searchMetadataComponents" {
  export default function searchMetadataComponents(param: {searchTerm: any, rowLimit: any}): Promise<any>;
}
declare module "@salesforce/apex/ImpactAnalysisController.getDependencyGraph" {
  export default function getDependencyGraph(param: {rootId: any, direction: any, maxNodes: any, maxIterations: any}): Promise<any>;
}
