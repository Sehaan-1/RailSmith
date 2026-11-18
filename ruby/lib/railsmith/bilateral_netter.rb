# frozen_string_literal: true
# typed: strict

module RailSmith
  # Stage 2 — flow compression. Mirrors Stripe's bilateral netting
  # optimization: opposing obligations on the same unordered currency
  # corridor cancel out, and only the net difference ever touches an
  # external bank (e.g. $100k USD -> EUR against $70k EUR -> USD
  # becomes a single $30k movement).
  #
  # The netter is deliberately pure over TransferIntent objects — it
  # needs no graph, so compression can run before routing (Stage 3)
  # and against any batch of instructions.
  module BilateralNetter
    extend T::Sig

    sig { params(transfers: T::Array[TransferIntent]).returns(NettingResult) }
    def self.net(transfers)
      transfers.each { |transfer| validate!(transfer) }
      grouped = transfers.group_by { |transfer| corridor_key(transfer) }

      summaries = T.let([], T::Array[NettingSummary])
      settlements = T.let([], T::Array[CompressedSettlement])

      grouped.each do |key, corridor_transfers|
        low = T.must(key[1])
        high = T.must(key[2])
        currency_ser = T.must(key[0])

        low_to_high = corridor_transfers.select { |t| t.source_node == low }.sum(&:amount_cents)
        high_to_low = corridor_transfers.sum(&:amount_cents) - low_to_high

        gross = low_to_high + high_to_low
        net = (low_to_high - high_to_low).abs
        saved = gross - net
        currency = T.must(corridor_transfers.first).currency
        # "eu ↔ us · USD" — ↔ and · written as escapes so the source
        # stays pure ASCII and matches the TS corridor strings exactly.
        corridor = "#{low} \u2194 #{high} \u00b7 #{currency_ser}"

        summaries << NettingSummary.new(
          corridor: corridor,
          gross_volume_cents: gross,
          netted_movement_cents: net,
          saved_volume_cents: saved,
          compression_bps: compression_bps(saved, gross)
        )

        next if net.zero?

        outbound = low_to_high > high_to_low
        settlements << CompressedSettlement.new(
          id: "net-#{key.join(':')}",
          source_node: outbound ? low : high,
          target_node: outbound ? high : low,
          amount_cents: net,
          currency: currency,
          corridor: corridor
        )
      end

      NettingResult.new(summaries: summaries, settlements: settlements)
    end

    sig { params(transfer: TransferIntent).void }
    def self.validate!(transfer)
      raise ArgumentError, "transfer #{transfer.id.inspect} has a negative amount" if transfer.amount_cents.negative?
      raise ArgumentError, "transfer #{transfer.id.inspect} is a self-transfer" if transfer.source_node == transfer.target_node
    end

    # Unordered corridor key: both directions of a pair net together,
    # but currencies never mix.
    sig { params(transfer: TransferIntent).returns(T::Array[String]) }
    def self.corridor_key(transfer)
      low, high = [transfer.source_node, transfer.target_node].sort
      [transfer.currency.serialize, T.must(low), T.must(high)]
    end

    sig { params(saved_cents: Integer, gross_cents: Integer).returns(Integer) }
    def self.compression_bps(saved_cents, gross_cents)
      gross_cents.zero? ? 0 : (saved_cents * 10_000) / gross_cents
    end

    private_class_method :validate!, :corridor_key, :compression_bps
  end
end
