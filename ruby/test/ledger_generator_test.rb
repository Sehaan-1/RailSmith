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

    assert_equal 4, postings.size
    assert_equal %w[tr-1:ach:debit tr-1:ach:credit tr-1:fx-sepa:debit tr-1:fx-sepa:credit], postings.map(&:id)
    assert postings.frozen?
    assert(postings.all?(&:frozen?))
    assert RailSmith::LedgerGenerator.balanced?(postings)
    assert_equal({ 'USD' => { debit: 5_000_000, credit: 5_000_000 } }, RailSmith::LedgerGenerator.totals(postings))
  end

  def test_double_entry_directions_per_hop
    hop = @graph.edges_from('us').select { |edge| edge.id == 'ach' }
    postings = RailSmith::LedgerGenerator.generate(@intent, hop)

    debit = postings.find { |p| p.direction == RailSmith::PostingDirection::Debit }
    credit = postings.find { |p| p.direction == RailSmith::PostingDirection::Credit }
    assert_equal 'us', debit.account_id
    assert_equal 'fx', credit.account_id
    assert_equal 2_500_000, debit.amount_cents
    assert_equal 'DEBIT', debit.direction.serialize
    assert_equal 'ach', credit.rail_edge_id
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
