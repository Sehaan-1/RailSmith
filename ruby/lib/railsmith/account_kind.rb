# frozen_string_literal: true
# typed: strict

module RailSmith
  # What a node in the money graph is: a fiat bank account, a
  # treasury FX hub, or a stablecoin wallet.
  class AccountKind < T::Enum
    enums do
      BankAccount = new('BANK_ACCOUNT')
      TreasuryHub = new('TREASURY_HUB')
      Wallet = new('WALLET')
    end
  end
end
