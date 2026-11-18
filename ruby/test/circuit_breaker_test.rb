# frozen_string_literal: true
# typed: true

require 'test_helper'

class CircuitBreakerTest < Minitest::Test
  def setup
    @breaker = RailSmith::CircuitBreaker.new
  end

  def test_needs_min_samples_before_tripping
    4.times { @breaker.record_failure('fx-sepa') }
    refute @breaker.tripped?('fx-sepa')
    @breaker.record_failure('fx-sepa')
    assert @breaker.tripped?('fx-sepa')
  end

  def test_trips_at_threshold
    6.times { @breaker.record_success('ach') }
    4.times { @breaker.record_failure('ach') }
    refute @breaker.tripped?('ach')
    2.times { @breaker.record_failure('ach') }
    assert @breaker.tripped?('ach')
  end

  def test_error_rate_and_samples
    assert_equal 0.0, @breaker.error_rate('nope')
    assert_equal 0, @breaker.sample_count('nope')
    @breaker.record_failure('x')
    @breaker.record_success('x')
    assert_in_delta 0.5, @breaker.error_rate('x')
    assert_equal 2, @breaker.sample_count('x')
  end

  def test_trip_reopens_route_and_ledger_stays_balanced
    graph = RailSmith::Fixtures.demo_graph
    router = RailSmith::GraphRouter.new(graph)

    before = router.route(source: 'us', target: 'eu', amount_cents: 2_500_000, hour_utc: 10, speed_weight: 0.15)
    assert_equal ['ach', 'fx-sepa'], before.optimal.path_edges.map(&:id)

    5.times { @breaker.record_failure('fx-sepa') }
    assert_equal ['fx-sepa'], @breaker.apply!(graph)
    assert_equal RailSmith::RailHealth::CircuitOpen, graph.edges.find { |e| e.id == 'fx-sepa' }.health

    after = router.route(source: 'us', target: 'eu', amount_cents: 2_500_000, hour_utc: 10, speed_weight: 0.15)
    assert_equal ['ach', 'fx-gb', 'gb-eu'], after.optimal.path_edges.map(&:id)
    exclusion = after.exclusions.find { |ex| ex.edge_id == 'fx-sepa' }
    assert_equal RailSmith::ExclusionReason::CircuitOpen, exclusion.reason

    intent = RailSmith::TransferIntent.new(
      id: 'tr-9', source_node: 'us', target_node: 'eu',
      amount_cents: 2_500_000, currency: RailSmith::Currency::USD
    )
    ledger = RailSmith::LedgerGenerator.generate(intent, after.optimal.path_edges)
    assert_equal 6, ledger.size
    assert RailSmith::LedgerGenerator.balanced?(ledger)
  end

  def test_recovery_restores_only_breaker_tripped_rails
    graph = RailSmith::Fixtures.demo_graph
    5.times { @breaker.record_failure('fx-sepa') }
    @breaker.apply!(graph)

    15.times { @breaker.record_success('fx-sepa') }
    assert_equal [], @breaker.apply!(graph)
    assert_equal RailSmith::RailHealth::Healthy, graph.edges.find { |e| e.id == 'fx-sepa' }.health

    manual = graph.edges.find { |e| e.id == 'ach' }
    manual.health = RailSmith::RailHealth::CircuitOpen
    @breaker.apply!(graph)
    assert_equal RailSmith::RailHealth::CircuitOpen, manual.health
  end

  def test_validation_and_reset
    assert_raises(ArgumentError) { RailSmith::CircuitBreaker.new(window_size: 0) }
    assert_raises(ArgumentError) { RailSmith::CircuitBreaker.new(min_samples: 30) }
    assert_raises(ArgumentError) { RailSmith::CircuitBreaker.new(error_threshold: 1.5) }
    assert_raises(ArgumentError) { RailSmith::CircuitBreaker.new(error_threshold: 0.3, recover_threshold: 0.4) }

    @breaker.record_failure('ach')
    @breaker.reset('ach')
    assert_equal 0, @breaker.sample_count('ach')
  end
end
