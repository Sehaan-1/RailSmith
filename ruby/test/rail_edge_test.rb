# frozen_string_literal: true
# typed: true

require 'test_helper'

class RailEdgeTest < Minitest::Test
  def build_edge(overrides = {})
    RailSmith::RailEdge.new(
      {
        id: 'ach',
        from_node: 'us',
        to_node: 'fx',
        rail_kind: RailSmith::RailKind::ACH,
        fixed_fee_cents: 15,
        spread_bps: 8,
        latency_ms: 4_800_000,
        cutoff_hour_utc: 14
      }.merge(overrides)
    )
  end

  def test_defaults
    edge = build_edge(cutoff_hour_utc: nil)
    assert_equal RailSmith::FX_RATE_SCALE, edge.fx_rate_scaled
    assert_equal 1_000_000, edge.fx_rate_scaled
    assert_nil edge.cutoff_hour_utc
    assert_equal RailSmith::RailHealth::Healthy, edge.health
    refute edge.circuit_open?
  end

  def test_fee_math_is_integer_cents
    edge = build_edge
    assert_equal 2_000, edge.variable_fee_cents(2_500_000)
    assert_equal 2_015, edge.total_fee_cents(2_500_000)
    assert_kind_of Integer, edge.variable_fee_cents(1)
  end

  def test_latency_helpers
    assert_in_delta 80.0, build_edge.latency_minutes, 0.0001
    assert_in_delta 0.375, build_edge(latency_ms: 22_500).latency_minutes, 0.0001
  end

  def test_cutoff_window
    edge = build_edge
    refute edge.past_cutoff?(13)
    assert edge.past_cutoff?(14)
    assert edge.past_cutoff?(23)
    refute build_edge(cutoff_hour_utc: nil).past_cutoff?(23)
  end

  def test_health_is_mutable_for_circuit_breakers
    edge = build_edge
    edge.health = RailSmith::RailHealth::Degraded
    assert_equal RailSmith::RailHealth::Degraded, edge.health
    refute edge.circuit_open?
    edge.health = RailSmith::RailHealth::CircuitOpen
    assert edge.circuit_open?
  end

  def test_rail_kind_serialization_matches_ts_engine
    assert_equal 'STABLECOIN_MINT', RailSmith::RailKind::StablecoinMint.serialize
    assert_equal 'STABLECOIN_BURN', RailSmith::RailKind::StablecoinBurn.serialize
    assert_equal 'FX_HUB', RailSmith::RailKind::FxHub.serialize
    assert_equal 'CIRCUIT_OPEN', RailSmith::RailHealth::CircuitOpen.serialize
  end
end
