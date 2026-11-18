# frozen_string_literal: true
# typed: strict

module RailSmith
  # One frozen double-entry record, inspired by Stripe Ledger: every
  # hop of a transfer debits the sending account and credits the
  # receiving account by the same amount in the same currency.
  class LedgerPosting < T::Struct
    const :id, String
    const :transfer_id, String
    const :account_id, String
    const :direction, PostingDirection
    const :amount_cents, Integer
    const :currency, Currency
    const :rail_edge_id, String
  end
end
