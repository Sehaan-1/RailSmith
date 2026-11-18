# frozen_string_literal: true
# typed: strict

module RailSmith
  # The output of a netting run: per-corridor summaries plus the
  # compressed settlements to dispatch, with aggregate totals for
  # the "cash movement eliminated" headline metric.
  class NettingResult < T::Struct
    extend T::Sig

    const :summaries, T::Array[NettingSummary]
    const :settlements, T::Array[CompressedSettlement]

    sig { returns(Integer) }
    def total_gross_cents
      summaries.sum(&:gross_volume_cents)
    end

    sig { returns(Integer) }
    def total_netted_cents
      summaries.sum(&:netted_movement_cents)
    end

    sig { returns(Integer) }
    def total_saved_cents
      summaries.sum(&:saved_volume_cents)
    end

    # Aggregate compression across every corridor, in basis points.
    sig { returns(Integer) }
    def compression_bps
      gross = total_gross_cents
      gross.zero? ? 0 : (total_saved_cents * 10_000) / gross
    end
  end
end
