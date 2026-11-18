# frozen_string_literal: true
# typed: strict

module RailSmith
  # Stage 4 — reconciliation. Emits balanced double-entry records for
  # a transfer's route: one DEBIT / CREDIT pair per hop, frozen at
  # creation, with the per-currency invariant checked before the
  # journal leaves the engine.
  module LedgerGenerator
    extend T::Sig

    sig { params(intent: TransferIntent, edges: T::Array[RailEdge]).returns(T::Array[LedgerPosting]) }
    def self.generate(intent, edges)
      raise ArgumentError, 'Ledger amount must be a non-negative integer of cents' if intent.amount_cents.negative?

      postings = T.let([], T::Array[LedgerPosting])
      edges.each do |edge|
        postings << LedgerPosting.new(
          id: "#{intent.id}:#{edge.id}:debit",
          transfer_id: intent.id,
          account_id: edge.from_node,
          direction: PostingDirection::Debit,
          amount_cents: intent.amount_cents,
          currency: intent.currency,
          rail_edge_id: edge.id
        ).freeze
        postings << LedgerPosting.new(
          id: "#{intent.id}:#{edge.id}:credit",
          transfer_id: intent.id,
          account_id: edge.to_node,
          direction: PostingDirection::Credit,
          amount_cents: intent.amount_cents,
          currency: intent.currency,
          rail_edge_id: edge.id
        ).freeze
      end

      assert_balanced!(postings)
      postings.freeze
    end

    # Per-currency debit/credit totals,
    # e.g. { 'USD' => { debit: 100, credit: 100 } }.
    sig { params(postings: T::Array[LedgerPosting]).returns(T::Hash[String, T::Hash[Symbol, Integer]]) }
    def self.totals(postings)
      result = T.let(
        Hash.new { |h, k| h[k] = { debit: 0, credit: 0 } },
        T::Hash[String, T::Hash[Symbol, Integer]]
      )
      postings.each do |posting|
        bucket = T.must(result[posting.currency.serialize])
        key = posting.direction == PostingDirection::Debit ? :debit : :credit
        bucket[key] = T.must(bucket[key]) + posting.amount_cents
      end
      result
    end

    sig { params(postings: T::Array[LedgerPosting]).returns(T::Boolean) }
    def self.balanced?(postings)
      totals(postings).all? { |_currency, t| T.must(t[:debit]) == T.must(t[:credit]) }
    end

    sig { params(postings: T::Array[LedgerPosting]).void }
    def self.assert_balanced!(postings)
      totals(postings).each do |currency, t|
        debit = T.must(t[:debit])
        credit = T.must(t[:credit])
        raise "Ledger invariant failed for #{currency}: #{debit} != #{credit}" if debit != credit
      end
    end
    private_class_method :assert_balanced!
  end
end
