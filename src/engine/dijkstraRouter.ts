import type {RailEdge,RouteQuote} from '../types/railsmith';
interface Candidate { path: RailEdge[]; cost: number }
function shortest(source:string,target:string,edges:readonly RailEdge[],hour:number,speed:number,blockedId?:string):Candidate|null {
 const dist=new Map<string,number>([[source,0]]),prev=new Map<string,RailEdge>(),unvisited=new Set<string>([source,...edges.flatMap(e=>[e.fromNodeId,e.toNodeId])]);
 while(unvisited.size){let node:string|undefined,best=Infinity;for(const id of unvisited){const d=dist.get(id)??Infinity;if(d<best){best=d;node=id}}if(node===undefined||best===Infinity)break;unvisited.delete(node);if(node===target)break;
  for(const edge of edges){if(edge.id===blockedId||edge.fromNodeId!==node)continue;if(edge.health==='CIRCUIT_OPEN'||(edge.cutoffHourUtc!==null&&hour>=edge.cutoffHourUtc))continue;const healthFactor=edge.health==='DEGRADED'?2:1;const weight=(edge.fixedFeeCents+edge.latencyMinutes*speed*15)*healthFactor;const next=best+weight;if(next<(dist.get(edge.toNodeId)??Infinity)){dist.set(edge.toNodeId,next);prev.set(edge.toNodeId,edge);unvisited.add(edge.toNodeId)}}
 }
 if(source!==target&&!prev.has(target))return null;const path:RailEdge[]=[];let cursor=target;while(cursor!==source){const edge=prev.get(cursor);if(!edge)return null;path.unshift(edge);cursor=edge.fromNodeId}return{path,cost:dist.get(target)??0};
}
function quote(candidate:Candidate,excluded:RouteQuote['excludedEdges']):RouteQuote{return{pathEdges:candidate.path,totalFeeCents:candidate.path.reduce((n,e)=>n+e.fixedFeeCents,0),estimatedMinutes:candidate.path.reduce((n,e)=>n+e.latencyMinutes,0),effectiveRateDisplay:`${candidate.path.reduce((n,e)=>n+e.spreadBps,0)} bps`,excludedEdges:excluded}}
/** Deterministic Dijkstra route; the runner-up is the best route found by excluding each winning edge in turn. */
export function route(source:string,target:string,edges:readonly RailEdge[],hour:number,speedWeight:number){
 const excluded:RouteQuote['excludedEdges']=[];for(const e of edges){if(e.health==='CIRCUIT_OPEN')excluded.push({edgeId:e.id,reason:'CIRCUIT_OPEN'});else if(e.cutoffHourUtc!==null&&hour>=e.cutoffHourUtc)excluded.push({edgeId:e.id,reason:'PAST_CUTOFF'});}
 const winner=shortest(source,target,edges,hour,speedWeight);let runner:Candidate|null=null;
 if(winner)for(const edge of winner.path){const alternative=shortest(source,target,edges,hour,speedWeight,edge.id);if(alternative&&(!runner||alternative.cost<runner.cost))runner=alternative}
 return{optimal:winner?quote(winner,excluded):null,runnerUp:runner?quote(runner,excluded):null};
}
