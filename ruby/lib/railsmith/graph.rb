# frozen_string_literal: true
# typed: strict

module RailSmith
  # The directed money graph: accounts as nodes, rails as weighted
  # edges. Corridor invariants are validated at construction time so
  # a malformed network fails fast, before any netting (Stage 2) or
  # routing (Stage 3) runs on it.
  class Graph
    extend T::Sig

    sig { params(nodes: T::Array[AccountNode], edges: T::Array[RailEdge]).void }
    def initialize(nodes: [], edges: [])
      @nodes = T.let({}, T::Hash[String, AccountNode])
      @edges = T.let({}, T::Hash[String, RailEdge])
      @adjacency = T.let(Hash.new { |h, k| h[k] = [] }, T::Hash[String, T::Array[RailEdge]])
      nodes.each { |node| add_node(node) }
      edges.each { |edge| add_edge(edge) }
    end

    sig { returns(T::Array[AccountNode]) }
    def nodes
      @nodes.values
    end

    sig { returns(T::Array[RailEdge]) }
    def edges
      @edges.values
    end

    sig { params(id: String).returns(T.nilable(AccountNode)) }
    def node(id)
      @nodes[id]
    end

    sig { params(id: String).returns(T.nilable(RailEdge)) }
    def edge(id)
      @edges[id]
    end

    sig { params(node: AccountNode).void }
    def add_node(node)
      raise ArgumentError, "duplicate account node id #{node.id.inspect}" if @nodes.key?(node.id)

      @nodes[node.id] = node
    end

    sig { params(edge: RailEdge).void }
    def add_edge(edge)
      raise ArgumentError, "duplicate rail edge id #{edge.id.inspect}" if @edges.key?(edge.id)

      validate_invariants!(edge)
      unless @nodes.key?(edge.from_node)
        raise ArgumentError, "rail #{edge.id.inspect} references unknown source #{edge.from_node.inspect}"
      end
      unless @nodes.key?(edge.to_node)
        raise ArgumentError, "rail #{edge.id.inspect} references unknown target #{edge.to_node.inspect}"
      end

      @edges[edge.id] = edge
      T.must(@adjacency[edge.from_node]) << edge
    end

    # Outgoing rails from a node, in insertion order. This is the
    # adjacency list Stage 3's Dijkstra walks.
    sig { params(node_id: String).returns(T::Array[RailEdge]) }
    def edges_from(node_id)
      @adjacency.fetch(node_id, [])
    end

    # Incoming rails to a node. Stage 2's bilateral netting groups
    # opposing flows along both directions of a corridor.
    sig { params(node_id: String).returns(T::Array[RailEdge]) }
    def edges_to(node_id)
      @edges.values.select { |edge| edge.to_node == node_id }
    end

    private

    sig { params(edge: RailEdge).void }
    def validate_invariants!(edge)
      raise ArgumentError, "rail #{edge.id.inspect} has a negative fixed fee" if edge.fixed_fee_cents < 0
      raise ArgumentError, "rail #{edge.id.inspect} has a negative spread" if edge.spread_bps < 0
      raise ArgumentError, "rail #{edge.id.inspect} spreads 100% or more" if edge.spread_bps >= 10_000
      raise ArgumentError, "rail #{edge.id.inspect} has a non-positive FX rate" if edge.fx_rate_scaled <= 0
      raise ArgumentError, "rail #{edge.id.inspect} has a non-positive latency" if edge.latency_ms <= 0

      cutoff = edge.cutoff_hour_utc
      return if cutoff.nil? || (0..23).cover?(cutoff)

      raise ArgumentError, "rail #{edge.id.inspect} has a cutoff hour outside 0..23"
    end
  end
end
