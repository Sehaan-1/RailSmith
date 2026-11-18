# frozen_string_literal: true
# typed: strict

require 'set'

module RailSmith
  # Stage 3 — cost vs. speed routing. Constrained Dijkstra over a
  # composite edge weight:
  #
  #   fee_cents(amount) + latency_minutes * speed_weight * 10
  #
  # speed_weight 0 routes cost-first, 1 routes speed-first, and the
  # best path may run traditional multi-hop FX (USD -> treasury hub
  # -> EUR) or a hybrid fiat-to-stablecoin bridge (USD -> USDC ->
  # MXN). Rails that tripped a circuit breaker or missed their daily
  # cutoff are excluded; degraded rails route at a 2x penalty. The
  # runner-up quote — the best route with each winning edge removed
  # in turn — is the failover path Stage 4 promotes.
  #
  # Weights are routing scores only; every reported money and latency
  # total stays an integer.
  class GraphRouter
    extend T::Sig

    LATENCY_WEIGHT = T.let(10.0, Float)
    DEGRADED_PENALTY = T.let(2.0, Float)

    class Candidate < T::Struct
      const :path, T::Array[RailEdge]
      const :cost, Float
    end
    private_constant :Candidate

    sig { params(graph: Graph).void }
    def initialize(graph)
      @graph = graph
    end

    sig do
      params(
        source: String,
        target: String,
        amount_cents: Integer,
        hour_utc: Integer,
        speed_weight: Float
      ).returns(RouteResult)
    end
    def route(source:, target:, amount_cents:, hour_utc:, speed_weight: 0.5)
      validate_query!(amount_cents, hour_utc, speed_weight)

      winner = shortest(source, target, amount_cents, hour_utc, speed_weight, nil)
      runner = T.let(nil, T.nilable(Candidate))
      if winner
        winner.path.each do |edge|
          alternative = shortest(source, target, amount_cents, hour_utc, speed_weight, edge.id)
          runner = alternative if alternative && (runner.nil? || alternative.cost < runner.cost)
        end
      end

      RouteResult.new(
        optimal: winner ? quote(winner, amount_cents) : nil,
        runner_up: runner ? quote(runner, amount_cents) : nil,
        exclusions: exclusions_at(hour_utc)
      )
    end

    private

    sig do
      params(
        source: String,
        target: String,
        amount_cents: Integer,
        hour_utc: Integer,
        speed_weight: Float,
        blocked_edge_id: T.nilable(String)
      ).returns(T.nilable(Candidate))
    end
    def shortest(source, target, amount_cents, hour_utc, speed_weight, blocked_edge_id)
      return Candidate.new(path: [], cost: 0.0) if source == target

      dist = T.let({ source => 0.0 }, T::Hash[String, Float])
      prev_edge = T.let({}, T::Hash[String, RailEdge])
      queue = T.let([[0.0, source]], T::Array[[Float, String]])
      visited = T.let(Set.new, T::Set[String])

      until queue.empty?
        queue.sort_by!(&:first)
        entry = T.must(queue.shift)
        cost_here = entry[0]
        current = entry[1]
        next if visited.include?(current)

        visited.add(current)
        break if current == target

        @graph.edges_from(current).each do |edge|
          next if edge.id == blocked_edge_id
          next unless eligible?(edge, hour_utc)

          next_cost = cost_here + composite_weight(edge, amount_cents, speed_weight)
          if next_cost < dist.fetch(edge.to_node, Float::INFINITY)
            dist[edge.to_node] = next_cost
            prev_edge[edge.to_node] = edge
            queue << [next_cost, edge.to_node]
          end
        end
      end

      return nil unless prev_edge.key?(target)

      path = T.let([], T::Array[RailEdge])
      cursor = target
      until cursor == source
        edge = T.must(prev_edge[cursor])
        path.unshift(edge)
        cursor = edge.from_node
      end
      Candidate.new(path: path, cost: dist.fetch(target, 0.0))
    end

    sig { params(edge: RailEdge, hour_utc: Integer).returns(T::Boolean) }
    def eligible?(edge, hour_utc)
      !edge.circuit_open? && !edge.past_cutoff?(hour_utc)
    end

    sig { params(edge: RailEdge, amount_cents: Integer, speed_weight: Float).returns(Float) }
    def composite_weight(edge, amount_cents, speed_weight)
      base = edge.total_fee_cents(amount_cents) + (edge.latency_minutes * speed_weight * LATENCY_WEIGHT)
      edge.health == RailHealth::Degraded ? base * DEGRADED_PENALTY : base
    end

    sig { params(hour_utc: Integer).returns(T::Array[RouteExclusion]) }
    def exclusions_at(hour_utc)
      @graph.edges.filter_map do |edge|
        if edge.circuit_open?
          RouteExclusion.new(edge_id: edge.id, reason: ExclusionReason::CircuitOpen)
        elsif edge.past_cutoff?(hour_utc)
          RouteExclusion.new(edge_id: edge.id, reason: ExclusionReason::PastCutoff)
        end
      end
    end

    sig { params(candidate: Candidate, amount_cents: Integer).returns(RouteQuote) }
    def quote(candidate, amount_cents)
      RouteQuote.new(
        path_edges: candidate.path,
        total_fee_cents: candidate.path.sum { |edge| edge.total_fee_cents(amount_cents) },
        total_latency_ms: candidate.path.sum(&:latency_ms),
        effective_spread_bps: candidate.path.sum(&:spread_bps)
      )
    end

    sig { params(amount_cents: Integer, hour_utc: Integer, speed_weight: Float).void }
    def validate_query!(amount_cents, hour_utc, speed_weight)
      raise ArgumentError, "hour_utc #{hour_utc} is outside 0..23" unless (0..23).cover?(hour_utc)
      raise ArgumentError, 'amount_cents must be non-negative' if amount_cents.negative?
      raise ArgumentError, "speed_weight #{speed_weight} is outside 0.0..1.0" unless (0.0..1.0).cover?(speed_weight)
    end
  end
end
