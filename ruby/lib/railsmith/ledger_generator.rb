# frozen_string_literal: true
# typed: strict

module RailSmith
  # Stage 4 — reconciliation. Emits frozen double-entry records for a
  # transfer's route. FX hops post both sides of the conversion through
  # a clearing account and carry the converted cents into the next hop.
  module LedgerGenerator
    extend T::Sig

    FX_CLEARING_ACCOUNT_ID = T.let('fx-clearing', String)

    sig do
      params(
        intent: TransferIntent,
        edges: T::Array[RailEdge],
        nodes: T::Array[AccountNode]
      ).returns(T::Array[LedgerPosting])
    end
    def self.generate(intent, edges, nodes: Fixtures.nodes)
      raise ArgumentError, 'Ledger amount must be a non-negative integer of cents' if intent.amount_cents.negative?

      currency_by_account = T.let({}, T::Hash[String, Currency])
      nodes.each { |node| currency_by_account[node.id] = node.currency }

      postings = T.let([], T::Array[LedgerPosting])
      current_amount = T.let(intent.amount_cents, Integer)
      current_currency = T.let(intent.currency, Currency)

      edges.each do |edge|
        source_currency = currency_by_account.fetch(edge.from_node, current_currency)
        target_currency = currency_by_account.fetch(edge.to_node, source_currency)
        unless source_currency == current_currency
          raise ArgumentError, "Ledger currency mismatch at #{edge.id}: expected #{current_currency.serialize}, got #{source_currency.serialize}"
        end

        converted_amount = (current_amount * edge.fx_rate_scaled) / FX_RATE_SCALE
        conversion = source_currency != target_currency || edge.fx_rate_scaled != FX_RATE_SCALE

        if conversion
          postings << LedgerPosting.new(
            id: "#{intent.id}:#{edge.id}:source-debit",
            transfer_id: intent.id,
            account_id: edge.from_node,
            direction: PostingDirection::Debit,
            amount_cents: current_amount,
            currency: source_currency,
            rail_edge_id: edge.id
          ).freeze
          postings << LedgerPosting.new(
            id: "#{intent.id}:#{edge.id}:source-fx-credit",
            transfer_id: intent.id,
            account_id: FX_CLEARING_ACCOUNT_ID,
            direction: PostingDirection::Credit,
            amount_cents: current_amount,
            currency: source_currency,
            rail_edge_id: edge.id
          ).freeze
          postings << LedgerPosting.new(
            id: "#{intent.id}:#{edge.id}:target-fx-debit",
            transfer_id: intent.id,
            account_id: FX_CLEARING_ACCOUNT_ID,
            direction: PostingDirection::Debit,
            amount_cents: converted_amount,
            currency: target_currency,
            rail_edge_id: edge.id
          ).freeze
          postings << LedgerPosting.new(
            id: "#{intent.id}:#{edge.id}:target-credit",
            transfer_id: intent.id,
            account_id: edge.to_node,
            direction: PostingDirection::Credit,
            amount_cents: converted_amount,
            currency: target_currency,
            rail_edge_id: edge.id
          ).freeze
        else
          postings << LedgerPosting.new(
            id: "#{intent.id}:#{edge.id}:debit",
            transfer_id: intent.id,
            account_id: edge.from_node,
            direction: PostingDirection::Debit,
            amount_cents: current_amount,
            currency: source_currency,
            rail_edge_id: edge.id
          ).freeze
          postings << LedgerPosting.new(
            id: "#{intent.id}:#{edge.id}:credit",
            transfer_id: intent.id,
            account_id: edge.to_node,
            direction: PostingDirection::Credit,
            amount_cents: converted_amount,
            currency: target_currency,
            rail_edge_id: edge.id
          ).freeze
        end

        current_amount = converted_amount
        current_currency = target_currency
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
