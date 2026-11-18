import type {AccountNode, CurrencyCode, LedgerPosting, RailEdge, TransferIntent} from '../types/railsmith';

const FX_RATE_SCALE = 1_000_000;
const FX_CLEARING_ACCOUNT_ID = 'fx-clearing';

/**
 * Creates a frozen double-entry journal. Same-currency hops keep the
 * debit/credit pair; FX hops add clearing-account entries in each currency,
 * then carry the converted amount forward to the next rail.
 */
export function generateLedger(
  intent: TransferIntent,
  edges: readonly RailEdge[],
  accounts: readonly AccountNode[] = [],
): readonly LedgerPosting[] {
  if (!Number.isSafeInteger(intent.amountCents) || intent.amountCents < 0) {
    throw new RangeError('Ledger amount must be non-negative integer cents');
  }

  const currencyByAccount = new Map(accounts.map((account) => [account.id, account.currency]));
  const postings: LedgerPosting[] = [];
  let amountCents = intent.amountCents;
  let currency: CurrencyCode = intent.currency;

  for (const edge of edges) {
    const sourceCurrency = currencyByAccount.get(edge.fromNodeId) ?? currency;
    const targetCurrency = currencyByAccount.get(edge.toNodeId) ?? sourceCurrency;
    if (sourceCurrency !== currency) {
      throw new Error(`Ledger currency mismatch at ${edge.id}: expected ${currency}, got ${sourceCurrency}`);
    }

    const convertedAmount = Math.floor(amountCents * edge.fxRateScaled / FX_RATE_SCALE);
    const converted = sourceCurrency !== targetCurrency || edge.fxRateScaled !== FX_RATE_SCALE;

    if (!converted) {
      postings.push(Object.freeze({
        id: `${intent.id}:${edge.id}:debit`, transferId: intent.id,
        accountId: edge.fromNodeId, direction: 'DEBIT', amountCents,
        currency: sourceCurrency, railEdgeId: edge.id,
      }));
      postings.push(Object.freeze({
        id: `${intent.id}:${edge.id}:credit`, transferId: intent.id,
        accountId: edge.toNodeId, direction: 'CREDIT', amountCents,
        currency: targetCurrency, railEdgeId: edge.id,
      }));
    } else {
      postings.push(Object.freeze({
        id: `${intent.id}:${edge.id}:source-debit`, transferId: intent.id,
        accountId: edge.fromNodeId, direction: 'DEBIT', amountCents,
        currency: sourceCurrency, railEdgeId: edge.id,
      }));
      postings.push(Object.freeze({
        id: `${intent.id}:${edge.id}:source-fx-credit`, transferId: intent.id,
        accountId: FX_CLEARING_ACCOUNT_ID, direction: 'CREDIT', amountCents,
        currency: sourceCurrency, railEdgeId: edge.id,
      }));
      postings.push(Object.freeze({
        id: `${intent.id}:${edge.id}:target-fx-debit`, transferId: intent.id,
        accountId: FX_CLEARING_ACCOUNT_ID, direction: 'DEBIT', amountCents: convertedAmount,
        currency: targetCurrency, railEdgeId: edge.id,
      }));
      postings.push(Object.freeze({
        id: `${intent.id}:${edge.id}:target-credit`, transferId: intent.id,
        accountId: edge.toNodeId, direction: 'CREDIT', amountCents: convertedAmount,
        currency: targetCurrency, railEdgeId: edge.id,
      }));
    }

    amountCents = convertedAmount;
    currency = targetCurrency;
  }

  const totals = new Map<string, {debit: number; credit: number}>();
  for (const row of postings) {
    const total = totals.get(row.currency) ?? {debit: 0, credit: 0};
    total[row.direction === 'DEBIT' ? 'debit' : 'credit'] += row.amountCents;
    totals.set(row.currency, total);
  }
  for (const [code, total] of totals) {
    if (total.debit !== total.credit) {
      throw new Error(`Ledger invariant failed for ${code}: ${total.debit} != ${total.credit}`);
    }
  }

  return Object.freeze(postings);
}
