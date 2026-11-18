# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'

require_relative 'railsmith/version'
require_relative 'railsmith/currency'
require_relative 'railsmith/account_kind'
require_relative 'railsmith/rail_kind'
require_relative 'railsmith/rail_health'
require_relative 'railsmith/account_node'
require_relative 'railsmith/rail_edge'
require_relative 'railsmith/transfer_intent'
require_relative 'railsmith/netting_summary'
require_relative 'railsmith/compressed_settlement'
require_relative 'railsmith/netting_result'
require_relative 'railsmith/bilateral_netter'
require_relative 'railsmith/graph'
require_relative 'railsmith/exclusion_reason'
require_relative 'railsmith/route_exclusion'
require_relative 'railsmith/route_quote'
require_relative 'railsmith/route_result'
require_relative 'railsmith/graph_router'
require_relative 'railsmith/fixtures'

# RailSmith: a Sorbet-typed multi-rail payment & FX graph engine,
# modeled on the architecture of Stripe's Global Payments and
# Treasury Network (GPTN). Accounts, FX hubs and stablecoin wallets
# are nodes; payment corridors are directed, weighted edges.
module RailSmith
end
