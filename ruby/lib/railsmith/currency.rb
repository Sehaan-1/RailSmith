# frozen_string_literal: true
# typed: strict

module RailSmith
  # Currencies supported by the network. Serialization values match
  # the TypeScript engine in `src/types/railsmith.ts` so the two
  # halves of the project can share payloads.
  class Currency < T::Enum
    enums do
      USD = new('USD')
      EUR = new('EUR')
      GBP = new('GBP')
      MXN = new('MXN')
      INR = new('INR')
      USDC = new('USDC')
    end
  end
end
