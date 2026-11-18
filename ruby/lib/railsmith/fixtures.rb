# frozen_string_literal: true
# typed: strict

module RailSmith
  # The demo network, mirroring the UI workbench one-for-one:
  # 10 accounts and 22 rails across USD/EUR/GBP/MXN/INR/USDC.
  # Latencies are written as `minutes * 60_000` (or literal ms for
  # the 22.5s stablecoin hops) so the conversion is visible at the
  # call site.
  module Fixtures
    extend T::Sig

    sig { returns(Graph) }
    def self.demo_graph
      Graph.new(nodes: nodes, edges: edges)
    end

    # The 120-instruction batch the UI workbench nets: 60 USD
    # transfers us -> eu against 60 eu -> us, grossing $2.4M and
    # compressing to a single $340k us -> eu settlement (~85.8%).
    sig { returns(T::Array[TransferIntent]) }
    def self.demo_transfers
      (0...120).map do |i|
        outbound = i.even?
        amount_cents = if outbound
          i < 40 ? 2_283_334 : 2_283_333
        else
          i < 40 ? 1_716_666 : 1_716_667
        end
        TransferIntent.new(
          id: "batch-#{i}",
          source_node: outbound ? 'us' : 'eu',
          target_node: outbound ? 'eu' : 'us',
          amount_cents: amount_cents,
          currency: Currency::USD
        )
      end
    end

    sig { returns(T::Array[AccountNode]) }
    def self.nodes
      [
        AccountNode.new(id: 'us', label: 'US Treasury', currency: Currency::USD, kind: AccountKind::TreasuryHub, region: 'New York'),
        AccountNode.new(id: 'fx', label: 'Treasury FX Hub', currency: Currency::EUR, kind: AccountKind::TreasuryHub, region: 'London'),
        AccountNode.new(id: 'eu', label: 'EU Clearing', currency: Currency::EUR, kind: AccountKind::BankAccount, region: 'Frankfurt'),
        AccountNode.new(id: 'gb', label: 'UK Clearing', currency: Currency::GBP, kind: AccountKind::BankAccount, region: 'London'),
        AccountNode.new(id: 'mx', label: 'MX Partner', currency: Currency::MXN, kind: AccountKind::BankAccount, region: 'Mexico City'),
        AccountNode.new(id: 'wallet', label: 'USDC Wallet', currency: Currency::USDC, kind: AccountKind::Wallet, region: 'On-chain'),
        AccountNode.new(id: 'in', label: 'India Payouts', currency: Currency::INR, kind: AccountKind::BankAccount, region: 'Mumbai'),
        AccountNode.new(id: 'sg', label: 'APAC Treasury', currency: Currency::USD, kind: AccountKind::TreasuryHub, region: 'Singapore'),
        AccountNode.new(id: 'ukfx', label: 'UK Liquidity', currency: Currency::GBP, kind: AccountKind::TreasuryHub, region: 'London'),
        AccountNode.new(id: 'eu2', label: 'EU Partner Bank', currency: Currency::EUR, kind: AccountKind::BankAccount, region: 'Paris')
      ]
    end

    sig { returns(T::Array[RailEdge]) }
    def self.edges
      [
        rail('ach', 'us', 'fx', RailKind::ACH, 15, 8, 80 * 60_000, 14),
        rail('wire-eu', 'us', 'eu', RailKind::Wire, 30_000, 35, 1_440 * 60_000, 14),
        rail('fx-sepa', 'fx', 'eu', RailKind::SEPA, 35, 4, 960 * 60_000, 17),
        rail('sepa-fps-direct', 'eu', 'gb', RailKind::FPS, 50, 12, 2 * 60_000),
        rail('eu-fx', 'eu', 'fx', RailKind::FxHub, 20, 5, 3 * 60_000),
        rail('fx-gb', 'fx', 'gb', RailKind::FPS, 30, 7, 4 * 60_000),
        rail('wire-mx', 'us', 'mx', RailKind::Wire, 3_500, 42, 600 * 60_000, 14),
        rail('mint', 'us', 'wallet', RailKind::StablecoinMint, 75, 2, 22_500),
        rail('burn', 'wallet', 'mx', RailKind::StablecoinBurn, 110, 3, 22_500),
        rail('wire-eu-return', 'eu', 'us', RailKind::Wire, 3_000, 30, 650 * 60_000, 14),
        rail('ach-us-eu', 'us', 'eu2', RailKind::ACH, 30_000, 10, 95 * 60_000, 14),
        rail('sepa-eu-eu', 'eu2', 'eu', RailKind::SEPA, 18, 3, 420 * 60_000, 17),
        rail('wire-eu-gb', 'eu', 'ukfx', RailKind::Wire, 900, 22, 90 * 60_000, 14),
        rail('fps-uk', 'ukfx', 'gb', RailKind::FPS, 25, 4, 2 * 60_000),
        rail('ach-us-in', 'us', 'in', RailKind::Wire, 2_500, 30, 480 * 60_000, 14),
        rail('in-sg', 'in', 'sg', RailKind::Wire, 1_200, 20, 240 * 60_000),
        rail('sg-us', 'sg', 'us', RailKind::Wire, 1_000, 18, 220 * 60_000),
        rail('sg-eu', 'sg', 'eu2', RailKind::Wire, 1_500, 25, 300 * 60_000),
        rail('gb-eu', 'gb', 'eu', RailKind::SEPA, 40, 8, 60 * 60_000, 17),
        rail('gb-mx', 'gb', 'mx', RailKind::Wire, 2_100, 35, 360 * 60_000),
        rail('eu-in', 'eu2', 'in', RailKind::Wire, 2_300, 32, 500 * 60_000),
        rail('mint-eu', 'eu2', 'wallet', RailKind::StablecoinMint, 90, 2, 22_500)
      ]
    end

    sig do
      params(
        id: String,
        from_node: String,
        to_node: String,
        rail_kind: RailKind,
        fixed_fee_cents: Integer,
        spread_bps: Integer,
        latency_ms: Integer,
        cutoff_hour_utc: T.nilable(Integer)
      ).returns(RailEdge)
    end
    def self.rail(id, from_node, to_node, rail_kind, fixed_fee_cents, spread_bps, latency_ms, cutoff_hour_utc = nil)
      RailEdge.new(
        id: id,
        from_node: from_node,
        to_node: to_node,
        rail_kind: rail_kind,
        fixed_fee_cents: fixed_fee_cents,
        spread_bps: spread_bps,
        latency_ms: latency_ms,
        cutoff_hour_utc: cutoff_hour_utc
      )
    end
    private_class_method :rail
  end
end
