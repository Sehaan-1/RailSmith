# frozen_string_literal: true
# typed: strict

module RailSmith
  # A single payment instruction waiting to be routed or netted.
  # Immutable: intents are inputs, never mutated in place.
  class TransferIntent < T::Struct
    const :id, String
    const :source_node, String
    const :target_node, String
    const :amount_cents, Integer
    const :currency, Currency
  end
end
