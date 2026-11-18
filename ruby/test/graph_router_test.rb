# frozen_string_literal: true
# typed: true

require 'test_helper'

class GraphRouterTest < Minitest::Test
  AMOUNT = 2_500_000 # $25k, the workbench default intent

  def setup
    @graph = RailSmith::Fixtures.demo_graph
    @router = RailSmith::GraphRouter.new(@graph)
  end

  def optimal_ids(result)
    result.optimal&.path_edges&.map(&:id)
  end

  def test_cost_first_route_is_cheapest_not_fastest
    result = @router.route(source: 'us', target: 'eu', amount_cents: AMOUNT, hour_utc: 10, speed_weight: 0.15)
    assert_equal ['ach', 'fx-sepa'], optimal_ids(result)

    quote = result.optimal
    assert_equal 3_050, quote.total_fee_cents
    assert_equal 62_400_000, quote.total_latency_ms
    assert_in_delta 1040.0, quote.estimated_minutes, 0.0001
    assert_equal 12, quote.effective_spread_bps
    assert_equal '12 bps', quote.effective_rate_display
    assert_equal 2, quote.hop_count
    refute quote.stablecoin_bridge?

    assert_empty result.exclusions
    assert_equal ['ach', 'fx-gb', 'gb-eu'], result.runner_up&.path_edges&.map(&:id)
  end

  def test_speed_first_prefers_more_faster_hops
    result = @router.route(source: 'us', target: 'eu', amount_cents: AMOUNT, hour_utc: 10, speed_weight: 1.0)
    assert_equal ['ach', 'fx-gb', 'gb-eu'], optimal_ids(result)

    quote = result.optimal
    assert_equal 5_835, quote.total_fee_cents
    assert_equal 8_640_000, quote.total_latency_ms
    assert_equal 3, quote.hop_count
  end

  def test_hybrid_stablecoin_bridge
    result = @router.route(source: 'us', target: 'mx', amount_cents: AMOUNT, hour_utc: 10, speed_weight: 0.8)
    assert_equal ['mint', 'burn'], optimal_ids(result)

    quote = result.optimal
    assert quote.stablecoin_bridge?
    assert_equal 1_435, quote.total_fee_cents
    assert_equal 45_000, quote.total_latency_ms
  end

  def test_after_hours_cutoffs_leave_only_the_bridge
    result = @router.route(source: 'us', target: 'eu', amount_cents: AMOUNT, hour_utc: 15, speed_weight: 0.15)
    assert_nil result.optimal
    assert_nil result.runner_up

    # The seven 14:00 UTC cutoff rails are out; 17:00 rails still ride.
    assert_equal 7, result.exclusions.size
    assert(result.exclusions.all? { |ex| ex.reason == RailSmith::ExclusionReason::PastCutoff })
    assert_includes result.exclusions.map(&:edge_id), 'ach'

    # The 24/7 stablecoin corridor survives every bank cutoff.
    overnight = @router.route(source: 'us', target: 'mx', amount_cents: AMOUNT, hour_utc: 15, speed_weight: 0.8)
    assert_equal ['mint', 'burn'], optimal_ids(overnight)
  end

  def test_circuit_breaker_reroutes
    fx_sepa = @graph.edges.find { |edge| edge.id == 'fx-sepa' }
    fx_sepa.health = RailSmith::RailHealth::CircuitOpen

    result = @router.route(source: 'us', target: 'eu', amount_cents: AMOUNT, hour_utc: 10, speed_weight: 0.15)
    assert_equal ['ach', 'fx-gb', 'gb-eu'], optimal_ids(result)

    exclusion = result.exclusions.find { |ex| ex.edge_id == 'fx-sepa' }
    refute_nil exclusion
    assert_equal RailSmith::ExclusionReason::CircuitOpen, exclusion.reason
  end

  def test_degraded_rail_routes_at_penalty_but_is_not_excluded
    fx_sepa = @graph.edges.find { |edge| edge.id == 'fx-sepa' }
    fx_sepa.health = RailSmith::RailHealth::Degraded

    result = @router.route(source: 'us', target: 'eu', amount_cents: AMOUNT, hour_utc: 10, speed_weight: 0.15)
    assert_equal ['ach', 'fx-gb', 'gb-eu'], optimal_ids(result)
    assert_empty result.exclusions
  end

  def test_self_route_is_free_and_unknown_source_has_no_route
    self_route = @router.route(source: 'us', target: 'us', amount_cents: AMOUNT, hour_utc: 10)
    assert_equal [], self_route.optimal.path_edges
    assert_equal 0, self_route.optimal.total_fee_cents
    assert_nil self_route.runner_up

    nope = @router.route(source: 'nope', target: 'eu', amount_cents: AMOUNT, hour_utc: 10)
    assert_nil nope.optimal
  end

  def test_query_validation
    assert_raises(ArgumentError) { @router.route(source: 'us', target: 'eu', amount_cents: -1, hour_utc: 10) }
    assert_raises(ArgumentError) { @router.route(source: 'us', target: 'eu', amount_cents: AMOUNT, hour_utc: 24) }
    assert_raises(ArgumentError) { @router.route(source: 'us', target: 'eu', amount_cents: AMOUNT, hour_utc: 10, speed_weight: 1.5) }
  end
end
