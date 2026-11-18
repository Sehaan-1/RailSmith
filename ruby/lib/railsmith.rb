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
require_relative 'railsmith/graph'
require_relative 'railsmith/fixtures'

# RailSmith: a Sorbet-typed multi-rail payment & FX graph engine,
# modeled on the architecture of Stripe's Global Payments and
# Treasury Network (GPTN). Accounts, FX hubs and stablecoin wallets
# are nodes; payment corridors are directed, weighted edges.
module RailSmith
end
