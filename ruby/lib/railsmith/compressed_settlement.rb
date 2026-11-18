# frozen_string_literal: true
# typed: strict

module RailSmith
  # The single net movement that survives bilateral netting on one
  # corridor, in the direction of the larger flow.
  class CompressedSettlement < T::Struct
    const :id, String
    const :source_node, String
    const :target_node, String
    const :amount_cents, Integer
    const :currency, Currency
    const :corridor, String
  end
end
