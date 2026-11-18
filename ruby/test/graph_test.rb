# frozen_string_literal: true
# typed: true

require 'test_helper'

class GraphTest < Minitest::Test
  def node_a
    RailSmith::AccountNode.new(id: 'a', label: 'A', currency: RailSmith::Currency::USD, kind: RailSmith::AccountKind::BankAccount, region: 'X')
  end

  def node_b
    RailSmith::AccountNode.new(id: 'b', label: 'B', currency: RailSmith::Currency::EUR, kind: RailSmith::AccountKind::TreasuryHub, region: 'Y')
  end

  def edge(overrides = {})
    RailSmith::RailEdge.new(
      {
        id: 'a-b',
        from_node: 'a',
        to_node: 'b',
        rail_kind: RailSmith::RailKind::SEPA,
        fixed_fee_cents: 35,
        spread_bps: 4,
        latency_ms: 57_600_000,
        cutoff_hour_utc: 17
      }.merge(overrides)
    )
  end

  def graph
    RailSmith::Graph.new(nodes: [node_a, node_b], edges: [edge])
  end

  def test_lookup_and_adjacency
    g = graph
    assert_equal 2, g.nodes.size
    assert_equal 'A', g.node('a')&.label
    assert_nil g.node('nope')
    assert_equal ['a-b'], g.edges_from('a').map(&:id)
    assert_empty g.edges_from('b')
    assert_equal ['a-b'], g.edges_to('b').map(&:id)
    assert_empty g.edges_to('a')
  end

  def test_duplicate_node_id_raises
    assert_raises(ArgumentError) { graph.add_node(node_a) }
  end

  def test_duplicate_edge_id_raises
    assert_raises(ArgumentError) { graph.add_edge(edge) }
  end

  def test_unknown_endpoints_raise
    g = RailSmith::Graph.new(nodes: [node_a])
    assert_raises(ArgumentError) { g.add_edge(edge) }
    assert_raises(ArgumentError) { RailSmith::Graph.new(nodes: [node_a, node_b], edges: [edge(from_node: 'ghost')]) }
  end

  def test_invariants
    bad = RailSmith::Graph.new(nodes: [node_a, node_b])
    assert_raises(ArgumentError) { bad.add_edge(edge(id: 'x1', fixed_fee_cents: -1)) }
    assert_raises(ArgumentError) { bad.add_edge(edge(id: 'x2', spread_bps: -1)) }
    assert_raises(ArgumentError) { bad.add_edge(edge(id: 'x3', spread_bps: 10_000)) }
    assert_raises(ArgumentError) { bad.add_edge(edge(id: 'x4', fx_rate_scaled: 0)) }
    assert_raises(ArgumentError) { bad.add_edge(edge(id: 'x5', latency_ms: 0)) }
    assert_raises(ArgumentError) { bad.add_edge(edge(id: 'x6', cutoff_hour_utc: 24)) }
    bad.add_edge(edge(id: 'ok', cutoff_hour_utc: 0))
    assert_equal 'ok', bad.edges.last.id
  end
end
