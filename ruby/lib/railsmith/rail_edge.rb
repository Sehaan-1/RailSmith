# frozen_string_literal: true
# typed: strict

module RailSmith
  # FX rates are stored scaled by FX_RATE_SCALE (a rate of 1.0 is
  # 1_000_000) so corridor math stays in integers and never touches
  # binary floating point.
  FX_RATE_SCALE = T.let(1_000_000, Integer)

  # A directed, weighted payment corridor between two accounts.
  #
  # Every magnitude is an integer: money in cents, spreads in basis
  # points, latency in milliseconds. Millisecond latency keeps a
  # sub-minute stablecoin hop (22.5s) exact — the starter sketch's
  # integer `latency_minutes` would round it to zero.
  #
  # `health` is mutable on purpose: Stage 4's circuit breakers trip
  # it at runtime while the corridor's economics stay frozen.
  class RailEdge < T::Struct
    extend T::Sig

    const :id, String
    const :from_node, String
    const :to_node, String
    const :rail_kind, RailKind
    const :fixed_fee_cents, Integer
    const :spread_bps, Integer
    const :fx_rate_scaled, Integer, default: FX_RATE_SCALE
    const :latency_ms, Integer
    const :cutoff_hour_utc, T.nilable(Integer), default: nil
    prop :health, RailHealth, default: RailHealth::Healthy

    # Spread (variable) fee for moving `amount_cents` across this
    # rail, floored to the cent — integer bps math throughout.
    sig { params(amount_cents: Integer).returns(Integer) }
    def variable_fee_cents(amount_cents)
      (amount_cents * spread_bps) / 10_000
    end

    # Total fee for moving `amount_cents` across this rail.
    sig { params(amount_cents: Integer).returns(Integer) }
    def total_fee_cents(amount_cents)
      fixed_fee_cents + variable_fee_cents(amount_cents)
    end

    sig { returns(Float) }
    def latency_minutes
      latency_ms / 60_000.0
    end

    # A rail with a cutoff is unusable at or after that UTC hour;
    # a nil cutoff settles 24/7.
    sig { params(hour_utc: Integer).returns(T::Boolean) }
    def past_cutoff?(hour_utc)
      cutoff = cutoff_hour_utc
      !cutoff.nil? && hour_utc >= cutoff
    end

    sig { returns(T::Boolean) }
    def circuit_open?
      health == RailHealth::CircuitOpen
    end
  end
end
