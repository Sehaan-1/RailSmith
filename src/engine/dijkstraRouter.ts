import type {RailEdge,RouteQuote} from '../types/railsmith';
export function route(source:string,target:string,edges:RailEdge[],hour:number,speedWeight:number){
 const excluded:RouteQuote['excludedEdges']=[]; const available=edges.filter(e=>{if(e.health==='CIRCUIT_OPEN'){excluded.push({edgeId:e.id,reason:'CIRCUIT_OPEN'});return false}if(e.cutoffHourUtc!==null&&hour>=e.cutoffHourUtc){excluded.push({edgeId:e.id,reason:'PAST_CUTOFF'});return false}return true});
 const paths:Array<{edges:RailEdge[];score:number}>=[];
 const walk=(node:string,path:RailEdge[],seen:Set<string>,score:number)=>{if(node===target){paths.push({edges:path,score});return}if(path.length>=8)return;for(const e of available.filter(x=>x.fromNodeId===node&&!seen.has(x.toNodeId))){const weight=e.fixedFeeCents+(e.latencyMinutes*speedWeight*15);walk(e.toNodeId,[...path,e],new Set([...seen,e.toNodeId]),score+weight)}};
 walk(source,[],new Set([source]),0);paths.sort((a,b)=>a.score-b.score);
 const quote=(p:typeof paths[number]):RouteQuote=>({pathEdges:p.edges,totalFeeCents:p.edges.reduce((n,e)=>n+e.fixedFeeCents,0),estimatedMinutes:p.edges.reduce((n,e)=>n+e.latencyMinutes,0),effectiveRateDisplay:`${p.edges.reduce((n,e)=>n+e.spreadBps,0)} bps`,excludedEdges:excluded});
 return {optimal:paths[0]?quote(paths[0]):null,runnerUp:paths[1]?quote(paths[1]):null};
}
