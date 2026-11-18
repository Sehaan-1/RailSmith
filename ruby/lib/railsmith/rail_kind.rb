# frozen_string_literal: true
# typed: strict

module RailSmith
  # The payment rail a corridor runs on, from slow-and-cheap ACH to
  # 24/7 stablecoin mint/burn bridges.
  class RailKind < T::Enum
    enums do
      ACH = new('ACH')
      SEPA = new('SEPA')
      Wire = new('WIRE')
      FxHub = new('FX_HUB')
      StablecoinMint = new('STABLECOIN_MINT')
      StablecoinBurn = new('STABLECOIN_BURN')
      FPS = new('FPS')
    end
  end
end
