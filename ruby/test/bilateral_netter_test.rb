# frozen_string_literal: true
# typed: true

require 'test_helper'

class BilateralNetterTest < Minitest::Test
  def intent(id, source, target, amount, currency = RailSmith::Currency::USD)
    RailSmith::TransferIntent.new(id: id, source_node: source, target_node: target, amount_cents: amount, currency: currency)
  end

  # The plan's headline example: $100k USD -> EUR against $70k
  # EUR -> USD compresses to a single $30k net movement.
  def test_plan_example
    result = RailSmith::BilateralNetter.net([
      intent('t1', 'us', 'eu', 10_000_000),
      intent('t2', 'eu', 'us', 7_000_000)
    ])

    assert_equal 1, result.summaries.size
    summary = result.summaries.first
    assert_equal "eu \u2194 us \u00b7 USD", summary.corridor
    assert_equal 17_000_000, summary.gross_volume_cents
    assert_equal 3_000_000, summary.netted_movement_cents
    assert_equal 14_000_000, summary.saved_volume_cents
    assert_equal 8_235, summary.compression_bps
    assert_in_delta 82.35, summary.compression_pct, 0.001

    assert_equal 1, result.settlements.size
    settlement = result.settlements.first
    assert_equal 'net-USD:eu:us', settlement.id
    assert_equal 'us', settlement.source_node
    assert_equal 'eu', settlement.target_node
    assert_equal 3_000_000, settlement.amount_cents
    assert_equal RailSmith::Currency::USD, settlement.currency

    assert_equal 17_000_000, result.total_gross_cents
    assert_equal 14_000_000, result.total_saved_cents
    assert_equal 8_235, result.compression_bps
  end

  def test_exact_opposition_leaves_no_settlement
    result = RailSmith::BilateralNetter.net([
      intent('t1', 'us', 'eu', 5_000_000),
      intent('t2', 'eu', 'us', 5_000_000)
    ])
    assert_empty result.settlements
    assert_equal 0, result.summaries.first.netted_movement_cents
    assert_equal 10_000, result.summaries.first.compression_bps
  end

  def test_corridors_are_unordered_but_currencies_never_mix
    result = RailSmith::BilateralNetter.net([
      intent('t1', 'us', 'eu', 1_000_000),
      intent('t2', 'eu', 'us', 400_000),
      intent('t3', 'gb', 'eu', 900_000, RailSmith::Currency::EUR)
    ])
    assert_equal 2, result.summaries.size
    usd = result.summaries.find { |s| s.corridor.include?('USD') }
    assert_equal 600_000, usd.netted_movement_cents
    assert_equal 'us', result.settlements.find { |s| s.currency == RailSmith::Currency::USD }.source_node
  end

  def test_aggregation_order_is_first_seen
    result = RailSmith::BilateralNetter.net([
      intent('t1', 'gb', 'eu', 100, RailSmith::Currency::GBP),
      intent('t2', 'us', 'eu', 100)
    ])
    assert_equal ["eu \u2194 gb \u00b7 GBP", "eu \u2194 us \u00b7 USD"], result.summaries.map(&:corridor)
  end

  def test_invalid_transfers_raise
    assert_raises(ArgumentError) { RailSmith::BilateralNetter.net([intent('bad', 'us', 'eu', -1)]) }
    assert_raises(ArgumentError) { RailSmith::BilateralNetter.net([intent('bad', 'us', 'us', 100)]) }
  end

  def test_empty_batch
    result = RailSmith::BilateralNetter.net([])
    assert_empty result.summaries
    assert_empty result.settlements
    assert_equal 0, result.total_gross_cents
    assert_equal 0, result.compression_bps
  end

  def test_demo_batch_matches_workbench_numbers
    result = RailSmith::BilateralNetter.net(RailSmith::Fixtures.demo_transfers)
    assert_equal 1, result.summaries.size
    assert_equal 240_000_000, result.total_gross_cents
    assert_equal 34_000_000, result.total_netted_cents
    assert_equal 206_000_000, result.total_saved_cents
    assert_equal 8_583, result.compression_bps

    settlement = result.settlements.first
    assert_equal 'us', settlement.source_node
    assert_equal 'eu', settlement.target_node
    assert_equal 34_000_000, settlement.amount_cents
  end
end
