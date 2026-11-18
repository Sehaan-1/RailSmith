# frozen_string_literal: true
# typed: true

require 'test_helper'

class LedgerGeneratorTest < Minitest::Test
  def setup
    @graph = RailSmith::Fixtures.demo_graph
    @router = RailSmith::GraphRouter.new(@graph)
    @intent = RailSmith::TransferIntent.new(
      id: 'tr-1', source_node: 'us', target_node: 'eu',
      amount_cents: 2_500_000, currency: RailSmith::Currency::USD
    )
  end

  def test_balanced_frozen_postings_for_routed_path
    result = @router.route(source: 'us', target: 'eu', amount_cents: @intent.amount_cents, hour_utc: 10, speed_weight: 0.15)
    postings = RailSmith::LedgerGenerator.generate(@intent, result.optimal.path_edges)

    assert_equal 6, postings.size
    assert_equal %w[
      tr-1:ach:source-debit tr-1:ach:source-fx-credit tr-1:ach:target-fx-debit tr-1:ach:target-credit
      tr-1:fx-sepa:debit tr-1:fx-sepa:credit
    ], postings.map(&:id)
    assert_equal 2_300_000, postings.find { |posting| posting.id == 'tr-1:ach:target-credit' }.amount_cents
    assert_equal RailSmith::Currency::EUR, postings.find { |posting| posting.id == 'tr-1:ach:target-credit' }.currency
    assert postings.frozen?
    assert(postings.all?(&:frozen?))
    assert RailSmith::LedgerGenerator.balanced?(postings)
    assert_equal({
      'USD' => { debit: 2_500_000, credit: 2_500_000 },
      'EUR' => { debit: 4_600_000, credit: 4_600_000 }
    }, RailSmith::LedgerGenerator.totals(postings))
  end

  def test_double_entry_directions_per_hop
    hop = @graph.edges_from('us').select { |edge| edge.id == 'ach' }
    postings = RailSmith::LedgerGenerator.generate(@intent, hop)

    source_debit = postings.find { |posting| posting.id.end_with?(':source-debit') }
    source_credit = postings.find { |posting| posting.id.end_with?(':source-fx-credit') }
    target_debit = postings.find { |posting| posting.id.end_with?(':target-fx-debit') }
    target_credit = postings.find { |posting| posting.id.end_with?(':target-credit') }
    assert_equal 'us', source_debit.account_id
    assert_equal 'fx-clearing', source_credit.account_id
    assert_equal 'USD', source_credit.currency.serialize
    assert_equal 2_500_000, source_debit.amount_cents
    assert_equal 'DEBIT', source_debit.direction.serialize
    assert_equal 2_300_000, target_debit.amount_cents
    assert_equal 'EUR', target_debit.currency.serialize
    assert_equal 'fx', target_credit.account_id
    assert_equal 'ach', target_credit.rail_edge_id
  end

  def test_empty_path_is_empty_and_balanced
    postings = RailSmith::LedgerGenerator.generate(@intent, [])
    assert_empty postings
    assert RailSmith::LedgerGenerator.balanced?(postings)
  end

  def test_negative_amount_raises
    bad = RailSmith::TransferIntent.new(
      id: 'tr-x', source_node: 'us', target_node: 'eu',
      amount_cents: -5, currency: RailSmith::Currency::USD
    )
    assert_raises(ArgumentError) { RailSmith::LedgerGenerator.generate(bad, []) }
  end

  def test_imbalance_detected_by_totals
    postings = [
      RailSmith::LedgerPosting.new(
        id: 'p1', transfer_id: 'tr-1', account_id: 'us',
        direction: RailSmith::PostingDirection::Debit, amount_cents: 100,
        currency: RailSmith::Currency::USD, rail_edge_id: 'ach'
      )
    ]
    refute RailSmith::LedgerGenerator.balanced?(postings)
    assert_equal({ 'USD' => { debit: 100, credit: 0 } }, RailSmith::LedgerGenerator.totals(postings))
  end
end
