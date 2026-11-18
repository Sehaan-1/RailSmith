# frozen_string_literal: true
# typed: strict

module RailSmith
  # Per-corridor outcome of bilateral netting: how much volume was
  # cancelled before any transfer touched an external bank.
  #
  # Compression is stored in basis points (85.83% == 8583) so the
  # engine stays integer-only; `compression_pct` exists for display.
  class NettingSummary < T::Struct
    const :corridor, String
    const :gross_volume_cents, Integer
    const :netted_movement_cents, Integer
    const :saved_volume_cents, Integer
    const :compression_bps, Integer

    sig { returns(Float) }
    def compression_pct
      compression_bps / 100.0
    end
  end
end
