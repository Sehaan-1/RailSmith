# frozen_string_literal: true
# typed: true

require 'test_helper'

class FixturesTest < Minitest::Test
  def setup
    @graph = RailSmith::Fixtures.demo_graph
  end

  def test_demo_network_shape
    assert_equal 10, @graph.nodes.size
    assert_equal 22, @graph.edges.size
    assert_equal @graph.nodes.map(&:id).uniq.size, @graph.nodes.size
  end

  def test_every_rail_starts_healthy
    assert @graph.edges.all? { |edge| edge.health == RailSmith::RailHealth::Healthy }
  end

  def test_stablecoin_hops_keep_subminute_latency
    mint = @graph.edges.find { |edge| edge.id == 'mint' }
    refute_nil mint
    assert_equal 22_500, mint&.latency_ms
    assert_nil mint&.cutoff_hour_utc
    assert_equal RailSmith::RailKind::StablecoinMint, mint&.rail_kind
  end

  def test_wire_cutoffs
    wire = @graph.edges.find { |edge| edge.id == 'wire-eu' }
    refute_nil wire
    assert_equal 30_000, wire&.fixed_fee_cents
    assert_equal 14, wire&.cutoff_hour_utc
  end

  def test_adjacency_matches_workbench
    assert_equal 6, @graph.edges_from('us').size
    assert_equal 3, @graph.edges_from('eu2').size
    assert_equal 2, @graph.edges_from('gb').size
    assert_equal 1, @graph.edges_from('wallet').size
    assert_empty @graph.edges_from('mx')
  end

  # The requirements call for ACH, SEPA, SWIFT wire, FX swap and
  # stablecoin bridge corridors, each represented as RailEdge
  # objects. Every one of those families has live edges in the demo
  # graph (SWIFT wire -> Wire, FX swap -> FxHub, bridge -> mint/burn).
  def test_every_required_corridor_family_is_represented
    kinds = @graph.edges.map(&:rail_kind).uniq
    [
      RailSmith::RailKind::ACH,
      RailSmith::RailKind::SEPA,
      RailSmith::RailKind::Wire,
      RailSmith::RailKind::FxHub,
      RailSmith::RailKind::StablecoinMint,
      RailSmith::RailKind::StablecoinBurn
    ].each { |kind| assert_includes kinds, kind }
  end
end
