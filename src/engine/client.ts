import {route as routeLocal} from './dijkstraRouter';
import {netTransfers} from './bilateralNetter';
import {generateLedger} from './ledgerGenerator';
import {evaluateCircuitBreaker, type CircuitBreakerSnapshot, type CircuitOutcome} from './circuitBreaker';
import type {LedgerPosting,NettingSummary,RailEdge,RouteQuote,TransferIntent} from '../types/railsmith';

/**
 * Engine client. Every query tries the Ruby engine API first (proxied
 * at /api by the dev server) and falls back transparently to the
 * bundled TypeScript engine when the API is unreachable — e.g. in
 * preview sandboxes without a Ruby toolchain. Both engines implement
 * identical semantics, so the only visible difference is the badge.
 */
export type EngineMode='ruby'|'typescript';
export interface Exclusion{edgeId:string;reason:'CIRCUIT_OPEN'|'PAST_CUTOFF'}
export interface EngineRoute{mode:EngineMode;optimal:RouteQuote|null;runnerUp:RouteQuote|null}
export interface EngineNet{mode:EngineMode;summaries:NettingSummary[]}
export interface EngineLedger{mode:EngineMode;postings:readonly LedgerPosting[]}
type ApiQuote=Omit<RouteQuote,'excludedEdges'>;

let probe:Promise<boolean>|null=null;
/** One cached health probe; a later request failure flips the engine off. */
export function engineAvailable():Promise<boolean>{
 if(!probe)probe=fetch('/api/health',{signal:AbortSignal.timeout(1500)}).then(r=>r.ok).catch(()=>false);
 return probe;
}
function markOffline(){probe=Promise.resolve(false)}
async function post<T>(path:string,body:unknown):Promise<T>{
 const res=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(4000)});
 if(!res.ok)throw new Error(`${path} answered ${res.status}`);
 return res.json() as Promise<T>;
}

export async function engineRoute(source:string,target:string,edges:readonly RailEdge[],amountCents:number,hour:number,speedWeight:number):Promise<EngineRoute>{
 if(await engineAvailable()){
  try{
   const data=await post<{optimal:ApiQuote|null;runnerUp:ApiQuote|null;exclusions:Exclusion[]}>('/api/route',{sourceNodeId:source,targetNodeId:target,amountCents,hourUtc:hour,speedWeight,edges});
   const withExclusions=(q:ApiQuote|null):RouteQuote|null=>q?{...q,excludedEdges:data.exclusions}:null;
   return{mode:'ruby',optimal:withExclusions(data.optimal),runnerUp:withExclusions(data.runnerUp)};
  }catch{markOffline()}
 }
 const local=routeLocal(source,target,edges,amountCents,hour,speedWeight);
 return{mode:'typescript',optimal:local.optimal,runnerUp:local.runnerUp};
}

export async function engineNet(transfers:readonly TransferIntent[]):Promise<EngineNet>{
 if(await engineAvailable()){
  try{
   const data=await post<{summaries:NettingSummary[]}>('/api/net',{transfers});
   return{mode:'ruby',summaries:data.summaries};
  }catch{markOffline()}
 }
 return{mode:'typescript',summaries:netTransfers(transfers).summaries};
}

export async function engineLedger(intent:TransferIntent,path:readonly RailEdge[]):Promise<EngineLedger>{
 if(path.length>0&&await engineAvailable()){
  try{
   const data=await post<{postings:LedgerPosting[]}>('/api/ledger',{id:intent.id,sourceNodeId:intent.sourceNodeId,targetNodeId:intent.targetNodeId,amountCents:intent.amountCents,currency:intent.currency,edgeIds:path.map(e=>e.id)});
   return{mode:'ruby',postings:data.postings};
  }catch{markOffline()}
 }
 return{mode:'typescript',postings:generateLedger(intent,path)};
}

export interface EngineCircuitBreaker extends CircuitBreakerSnapshot {mode:EngineMode}

/** Replays the current signal history through the Ruby breaker, with an equivalent local fallback. */
export async function engineCircuitBreaker(outcomes:readonly CircuitOutcome[],edges:readonly RailEdge[]):Promise<EngineCircuitBreaker>{
 if(await engineAvailable()){
  try{
   const data=await post<CircuitBreakerSnapshot>('/api/circuit-breaker',{outcomes});
   return{mode:'ruby',...data};
  }catch{markOffline()}
 }
 return{mode:'typescript',...evaluateCircuitBreaker(outcomes,edges.map(edge=>edge.id))};
}
