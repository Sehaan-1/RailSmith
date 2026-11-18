# frozen_string_literal: true
# typed: true

require 'test_helper'

class AccountNodeTest < Minitest::Test
  def build_node
    RailSmith::AccountNode.new(
      id: 'us',
      label: 'US Treasury',
      currency: RailSmith::Currency::USD,
      kind: RailSmith::AccountKind::TreasuryHub,
      region: 'New York'
    )
  end

  def test_fields
    node = build_node
    assert_equal 'us', node.id
    assert_equal 'US Treasury', node.label
    assert_equal RailSmith::Currency::USD, node.currency
    assert_equal RailSmith::AccountKind::TreasuryHub, node.kind
    assert_equal 'New York', node.region
  end

  def test_const_fields_have_no_setters
    assert_raises(NoMethodError) { build_node.id = 'other' }
    assert_raises(NoMethodError) { build_node.currency = RailSmith::Currency::EUR }
  end

  def test_enum_serialization_matches_ts_engine
    assert_equal 'USD', RailSmith::Currency::USD.serialize
    assert_equal 'USDC', RailSmith::Currency::USDC.serialize
    assert_equal 'BANK_ACCOUNT', RailSmith::AccountKind::BankAccount.serialize
    assert_equal 'TREASURY_HUB', RailSmith::AccountKind::TreasuryHub.serialize
    assert_equal 'WALLET', RailSmith::AccountKind::Wallet.serialize
  end

  def test_serialization_round_trip
    copy = RailSmith::AccountNode.from_hash(build_node.serialize)
    assert_equal 'us', copy.id
    assert_equal RailSmith::Currency::USD, copy.currency
    assert_equal RailSmith::AccountKind::TreasuryHub, copy.kind
  end
end
