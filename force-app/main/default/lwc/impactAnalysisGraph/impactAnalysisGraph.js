import { LightningElement, track } from 'lwc';
import searchMetadataComponents from '@salesforce/apex/ImpactAnalysisController.searchMetadataComponents';
import getDependencyGraph from '@salesforce/apex/ImpactAnalysisController.getDependencyGraph';

const SVG_NS = 'http://www.w3.org/2000/svg';

export default class ImpactAnalysisGraph extends LightningElement {
    searchTerm = '';
    direction = 'DOWNSTREAM';
    loading = false;

    /** @type {Array<{id:string,name:string,type:string}>} */
    selectionBuffer = [];

    @track hits = [];

    columns = [
        { label: 'Name', fieldName: 'name', hideDefaultActions: true },
        { label: 'Type', fieldName: 'type', hideDefaultActions: true }
    ];

    directionOptions = [
        { label: 'Impact ↓ depends on starting item', value: 'DOWNSTREAM' },
        { label: 'Dependencies ↑ this item relies on', value: 'UPSTREAM' }
    ];

    graphMessage = '';

    connectedCallback() {
        this.direction = this.directionOptions[0].value;
    }

    handleSearchTermChange(event) {
        this.searchTerm = event.target.value;
    }

    handleDirectionChange(event) {
        this.direction = event.detail.value;
    }

    handleDatatableSelection(event) {
        this.selectionBuffer = event.detail.selectedRows || [];
    }

    async handleSearch() {
        this.loading = true;
        this.graphMessage = '';
        this.hits = [];
        this.selectionBuffer = [];
        this.resetGraphSurface();
        try {
            const results = await searchMetadataComponents({
                searchTerm: this.searchTerm,
                rowLimit: 15
            });
            this.hits = results || [];
        } catch (e) {
            this.graphMessage = this.reduceError(e);
        } finally {
            this.loading = false;
        }
    }

    async handleBuildGraph() {
        const row =
            this.selectionBuffer && this.selectionBuffer.length
                ? this.selectionBuffer[0]
                : null;
        if (!row || !row.id) {
            this.graphMessage = 'Select a metadata row before building the graph.';
            return;
        }

        this.loading = true;
        this.graphMessage = '';
        this.resetGraphSurface();
        try {
            const payload = await getDependencyGraph({
                rootId: row.id,
                direction: this.direction,
                maxNodes: 200,
                maxIterations: 40
            });

            if (payload.errorMessage) {
                this.graphMessage = payload.errorMessage;
                return;
            }

            if (payload.infoMessage) {
                this.graphMessage = payload.infoMessage;
            }
            this.paintGraph(payload.nodes || [], payload.edges || []);
        } catch (e) {
            this.graphMessage = this.reduceError(e);
        } finally {
            this.loading = false;
        }
    }

    reduceError(error) {
        if (!error) {
            return 'Unknown error';
        }
        if (Array.isArray(error.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (error.body && typeof error.body.message === 'string') {
            return error.body.message;
        }
        if (typeof error.message === 'string') {
            return error.message;
        }
        return 'Request failed.';
    }

    resetGraphSurface() {
        const host = this.template.querySelector('[data-role="graph-host"]');
        if (host) {
            host.innerHTML = '';
        }
    }

    paintGraph(nodes, edges) {
        const host = this.template.querySelector('[data-role="graph-host"]');
        if (!host) {
            return;
        }
        host.innerHTML = '';

        if (!nodes.length) {
            host.appendChild(this.svgFallback('Nothing to chart for this neighborhood yet.'));
            return;
        }

        const width = Math.max(host.clientWidth || 920, 640);
        const height = Math.min(640, Math.max(440, 120 + nodes.length * 24));

        const svg = document.createElementNS(SVG_NS, 'svg');
        svg.setAttribute('width', String(width));
        svg.setAttribute('height', String(height));
        svg.appendChild(this.svgLegend(width));

        const rootId = nodes.find((n) => n.isRoot)?.id || nodes[0].id;
        const coords = layoutGraph(rootId, nodes, edges, width, height);

        edges.forEach((edge) => {
            const from = coords.get(edge.fromId);
            const to = coords.get(edge.toId);
            if (!from || !to) {
                return;
            }
            const line = document.createElementNS(SVG_NS, 'line');
            line.setAttribute('x1', String(from.x));
            line.setAttribute('y1', String(from.y));
            line.setAttribute('x2', String(to.x));
            line.setAttribute('y2', String(to.y));
            line.setAttribute('stroke', '#c9d4f0');
            line.setAttribute('stroke-linecap', 'round');
            line.setAttribute('stroke-width', '1.3');
            svg.appendChild(line);
        });

        nodes.forEach((n) => {
            const xy = coords.get(n.id);
            if (!xy) {
                return;
            }
            const group = document.createElementNS(SVG_NS, 'g');
            group.setAttribute('transform', `translate(${xy.x}, ${xy.y})`);

            const circle = document.createElementNS(SVG_NS, 'circle');
            circle.setAttribute('r', n.isRoot ? '24' : '18');
            circle.setAttribute(
                'fill',
                n.isRoot ? '#fe9339' : n.type === 'ApexTrigger' ? '#059669' : '#0176d3'
            );
            circle.setAttribute('stroke', '#032d60');
            circle.setAttribute('stroke-width', '1.5');

            const label = document.createElementNS(SVG_NS, 'text');
            label.setAttribute('x', '0');
            label.setAttribute('y', '4');
            label.setAttribute('text-anchor', 'middle');
            label.setAttribute('fill', '#ffffff');
            label.setAttribute('font-size', '11');
            label.setAttribute('font-family', '"Salesforce Sans", Arial');
            label.textContent = truncateText(`${n.name || n.id}`, 18);

            const sub = document.createElementNS(SVG_NS, 'text');
            sub.setAttribute('x', '0');
            sub.setAttribute('y', '38');
            sub.setAttribute('text-anchor', 'middle');
            sub.setAttribute('fill', '#3e3e3c');
            sub.setAttribute('font-size', '10');
            sub.setAttribute('font-family', '"Salesforce Sans", Arial');
            sub.textContent = truncateText(`${n.type || 'Metadata'}`, 24);

            group.appendChild(circle);
            group.appendChild(label);
            group.appendChild(sub);
            svg.appendChild(group);
        });

        host.appendChild(svg);
    }

    svgLegend(canvasWidth) {
        const legend = document.createElementNS(SVG_NS, 'g');
        legend.setAttribute('transform', 'translate(16,26)');

        const title = document.createElementNS(SVG_NS, 'text');
        title.setAttribute('fill', '#3e3e3c');
        title.setAttribute('font-family', '"Salesforce Sans", Arial');
        title.setAttribute('font-size', '12');
        title.setAttribute('font-weight', '600');
        title.textContent =
            canvasWidth >= 760
                ? 'Arrows radiate outward from upstream nodes to dependents (impact view). Dependencies view reverses the traversal.'
                : 'Arrows highlight dependent metadata.';

        legend.appendChild(title);
        return legend;
    }

    svgFallback(message) {
        const svg = document.createElementNS(SVG_NS, 'svg');
        svg.setAttribute('width', '640');
        svg.setAttribute('height', '80');
        const text = document.createElementNS(SVG_NS, 'text');
        text.setAttribute('fill', '#3e3e3c');
        text.setAttribute('font-family', '"Salesforce Sans", Arial');
        text.setAttribute('font-size', '13');
        text.setAttribute('x', '16');
        text.setAttribute('y', '40');
        text.textContent = message;
        svg.appendChild(text);
        return svg;
    }
}

/**
 * Layers nodes by breadth-first depth from root along directed edges (from→to).
 * @returns {Map<string, {x:number, y:number}>}
 */
function layoutGraph(rootId, nodes, edges, width, height) {
    /** @type {Map<string, string[]>} */
    const children = new Map();
    edges.forEach((edge) => {
        if (!children.has(edge.fromId)) {
            children.set(edge.fromId, []);
        }
        children.get(edge.fromId).push(edge.toId);
    });

    /** @type {Map<string, number>} */
    const depth = new Map();
    depth.set(rootId, 0);
    const queue = [rootId];

    while (queue.length) {
        const id = queue.shift();
        const d = depth.get(id) ?? 0;
        children.get(id)?.forEach((child) => {
            if (!depth.has(child)) {
                depth.set(child, d + 1);
                queue.push(child);
            }
        });
    }

    nodes.forEach((node) => {
        if (!depth.has(node.id)) {
            depth.set(node.id, 998);
        }
    });

    /** @type {Map<number, string[]>} */
    const levels = new Map();
    [...depth.entries()]
        .sort((a, b) => {
            const diff = a[1] - b[1];
            if (diff !== 0) {
                return diff;
            }
            return a[0].localeCompare(b[0]);
        })
        .forEach(([nodeId, d]) => {
            if (!levels.has(d)) {
                levels.set(d, []);
            }
            levels.get(d).push(nodeId);
        });

    let maxOccupancy = 0;
    levels.forEach((list) => {
        maxOccupancy = Math.max(maxOccupancy, list.length || 1);
    });
    maxOccupancy = Math.max(maxOccupancy, 1);

    const deepest = levels.size ? [...levels.keys()].reduce((acc, curr) => Math.max(acc, curr), 0) : 0;
    const colCount = deepest + 1;
    const colWidth = Math.max(180, Math.min(260, Math.floor(width / Math.max(colCount, 1))));
    const rowPitch = Math.max(88, Math.min(136, Math.floor((height - 120) / maxOccupancy)));

    /** @type {Map<string, {x:number,y:number}>} */
    const pos = new Map();

    levels.forEach((list, d) => {
        const sorted = [...list].sort((a, b) => {
            const nameA =
                nodes.find((n) => n.id === a)?.name?.toLowerCase() || '';
            const nameB =
                nodes.find((n) => n.id === b)?.name?.toLowerCase() || '';
            return nameA.localeCompare(nameB);
        });
        const x = 72 + d * colWidth;
        const verticalOffset =
            sorted.length >= maxOccupancy ? 0 : ((maxOccupancy - sorted.length) * rowPitch) / 2;
        sorted.forEach((nodeId, idx) => {
            const y = 84 + verticalOffset + idx * rowPitch;
            pos.set(nodeId, { x, y });
        });
    });

    return pos;
}

function truncateText(value, limit) {
    if (!value) {
        return '';
    }
    if (value.length <= limit) {
        return value;
    }
    return `${value.slice(0, Math.max(limit - 1, 1))}…`;
}
