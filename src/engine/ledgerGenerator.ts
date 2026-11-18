import type {LedgerPosting, RailEdge, TransferIntent} from '../types/railsmith';

/** Creates a frozen balanced journal pair for each route hop; totals are checked per currency. */
export function generateLedger(intent: TransferIntent, edges: readonly RailEdge[]): readonly LedgerPosting[] {
  if (!Number.isSafeInteger(intent.amountCents) || intent.amountCents < 0) throw new RangeError('Ledger amount must be non-negative integer cents');
  const postings: LedgerPosting[] = [];
  for (const edge of edges) {
    const currency = intent.currency;
    postings.push(Object.freeze({ id: `${intent.id}:${edge.id}:debit`, transferId: intent.id, accountId: edge.fromNodeId, direction: 'DEBIT', amountCents: intent.amountCents, currency, railEdgeId: edge.id }));
    postings.push(Object.freeze({ id: `${intent.id}:${edge.id}:credit`, transferId: intent.id, accountId: edge.toNodeId, direction: 'CREDIT', amountCents: intent.amountCents, currency, railEdgeId: edge.id }));
  }
  const totals = new Map<string, { debit: number; credit: number }>();
  for (const row of postings) { const total = totals.get(row.currency) ?? { debit: 0, credit: 0 }; total[row.direction === 'DEBIT' ? 'debit' : 'credit'] += row.amountCents; totals.set(row.currency, total); }
  for (const [currency, total] of totals) if (total.debit !== total.credit) throw new Error(`Ledger invariant failed for ${currency}: ${total.debit} != ${total.credit}`);
  return Object.freeze(postings);
}
