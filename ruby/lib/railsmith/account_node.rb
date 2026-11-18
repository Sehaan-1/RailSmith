# frozen_string_literal: true
# typed: strict

module RailSmith
  # A node in the money graph: a fiat bank account, a treasury FX
  # hub, or a stablecoin wallet. Nodes are immutable; operational
  # state lives on edges, not accounts.
  class AccountNode < T::Struct
    const :id, String
    const :label, String
    const :currency, Currency
    const :kind, AccountKind
    const :region, String
  end
end
