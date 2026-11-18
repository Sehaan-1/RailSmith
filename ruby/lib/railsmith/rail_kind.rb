# frozen_string_literal: true
# typed: strict

module RailSmith
  # The payment rail a corridor runs on, from slow-and-cheap ACH to
  # 24/7 stablecoin mint/burn bridges. Every corridor family in the
  # requirements is representable:
  #
  #   ACH                -> ACH
  #   SEPA               -> SEPA
  #   SWIFT wire         -> Wire
  #   FX swap            -> FxHub (conversion at a treasury FX hub)
  #   Stablecoin bridge  -> StablecoinMint + StablecoinBurn pair
  #
  # FPS instant payments ride along as FPS.
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
