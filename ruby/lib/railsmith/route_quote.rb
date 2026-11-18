# frozen_string_literal: true
# typed: strict

module RailSmith
  # A priced multi-hop path between two accounts. Money stays integer
  # cents (fixed + spread fees for the queried amount), latency stays
  # integer milliseconds.
  class RouteQuote < T::Struct
    const :path_edges, T::Array[RailEdge]
    const :total_fee_cents, Integer
    const :total_latency_ms, Integer
    const :effective_spread_bps, Integer

    sig { returns(Integer) }
    def hop_count
      path_edges.size
    end

    sig { returns(Float) }
    def estimated_minutes
      total_latency_ms / 60_000.0
    end

    # Display parity with the TypeScript engine's effectiveRateDisplay.
    sig { returns(String) }
    def effective_rate_display
      "#{effective_spread_bps} bps"
    end

    # True when the path bridges fiat over stablecoin rails
    # (e.g. USD -> USDC -> MXN).
    sig { returns(T::Boolean) }
    def stablecoin_bridge?
      path_edges.any? do |edge|
        edge.rail_kind == RailKind::StablecoinMint || edge.rail_kind == RailKind::StablecoinBurn
      end
    end
  end
end
