import type {NettingSummary, TransferIntent} from '../types/railsmith';

export interface CompressedSettlementTransfer {
  id: string; sourceNodeId: string; targetNodeId: string;
  amountCents: number; currency: TransferIntent['currency']; corridor: string;
}
export interface NettingResult { summaries: NettingSummary[]; settlements: CompressedSettlementTransfer[] }

/** Nets opposing instructions on an unordered corridor, preserving currency and direction. */
export function netTransfers(transfers: readonly TransferIntent[]): NettingResult {
  const groups = new Map<string, { low: string; high: string; currency: TransferIntent['currency']; lowToHigh: number; highToLow: number }>();
  for (const t of transfers) {
    if (!Number.isSafeInteger(t.amountCents) || t.amountCents < 0) throw new RangeError(`Invalid amount for ${t.id}`);
    const [low, high] = [t.sourceNodeId, t.targetNodeId].sort();
    const key = `${t.currency}:${low}:${high}`;
    const g = groups.get(key) ?? { low, high, currency: t.currency, lowToHigh: 0, highToLow: 0 };
    if (t.sourceNodeId === low) g.lowToHigh += t.amountCents; else g.highToLow += t.amountCents;
    groups.set(key, g);
  }
  const summaries: NettingSummary[] = [], settlements: CompressedSettlementTransfer[] = [];
  for (const [key, g] of groups) {
    const gross = g.lowToHigh + g.highToLow, net = Math.abs(g.lowToHigh - g.highToLow);
    const saved = gross - net;
    summaries.push({ corridor: `${g.low} ↔ ${g.high} · ${g.currency}`, grossVolumeCents: gross, nettedMovementCents: net, savedVolumeCents: saved, compressionPct: gross ? Math.floor(saved * 10000 / gross) / 100 : 0 });
    if (net) settlements.push({ id: `net-${key}`, sourceNodeId: g.lowToHigh > g.highToLow ? g.low : g.high, targetNodeId: g.lowToHigh > g.highToLow ? g.high : g.low, amountCents: net, currency: g.currency, corridor: `${g.low} ↔ ${g.high}` });
  }
  return { summaries, settlements };
}
