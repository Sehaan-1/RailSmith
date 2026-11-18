# frozen_string_literal: true
# typed: strict

module RailSmith
  # Why a rail was excluded from a routing query. Serialization
  # matches the TypeScript engine.
  class ExclusionReason < T::Enum
    enums do
      CircuitOpen = new('CIRCUIT_OPEN')
      PastCutoff = new('PAST_CUTOFF')
    end
  end
end
