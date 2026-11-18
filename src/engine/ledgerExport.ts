import type {LedgerPosting, TransferIntent} from '../types/railsmith';

export type LedgerExportFormat = 'csv' | 'json';

export interface LedgerExportData {
  transfer: Pick<TransferIntent, 'id' | 'sourceNodeId' | 'targetNodeId' | 'amountCents' | 'currency'>;
  postings: readonly LedgerPosting[];
  totals: Record<string, {debit: number; credit: number}>;
  balanced: boolean;
}

const columns: (keyof LedgerPosting)[] = [
  'id', 'transferId', 'accountId', 'direction', 'amountCents', 'currency', 'railEdgeId',
];

function csvCell(value: unknown): string {
  const text = String(value ?? '');
  return /[",\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

export function ledgerAsCsv(postings: readonly LedgerPosting[]): string {
  const header = columns.join(',');
  const rows = postings.map((posting) => columns.map((column) => csvCell(posting[column])).join(','));
  return [header, ...rows].join('\r\n') + '\r\n';
}

export function ledgerAsJson(data: LedgerExportData): string {
  return `${JSON.stringify({version: 1, ...data}, null, 2)}\n`;
}
