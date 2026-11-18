# RailSmith engine (Ruby + Sorbet)

A Sorbet-typed multi-rail payment & FX graph engine, modeled on the
architecture of Stripe's Global Payments and Treasury Network
(GPTN). Accounts, treasury FX hubs and stablecoin wallets are nodes;
payment corridors (ACH, SEPA, wire, FX swap, stablecoin mint/burn)
are directed, weighted edges with fixed fees, basis-point spreads,
settlement latency and daily cutoff windows.

This directory currently holds **Stage 1 (typed graph schema)** and
**Stage 2 (flow compression)**. Later stages build on them:

1. **Typed graph schema** (done) — `AccountNode` / `RailEdge` structs, enums,
   and a `Graph` container that validates corridor invariants up front.
2. **Flow compression** (done) — `BilateralNetter` cancels opposing
   obligations per corridor before any transfer touches an external bank.
3. **Cost vs. speed routing** — constrained Dijkstra over a composite
   edge weight (`alpha * fee_cents + beta * settlement_minutes`),
   including hybrid fiat → stablecoin bridges.
4. **Resilience & reconciliation** — per-rail circuit breakers with
   automatic failover, and balanced double-entry records.

## Layout

```
lib/railsmith/
  currency.rb       Currency enum (USD, EUR, GBP, MXN, INR, USDC)
  account_kind.rb   AccountKind enum (bank account, treasury hub, wallet)
  rail_kind.rb      RailKind enum: ACH, SEPA, WIRE (SWIFT wire),
                    FX_HUB (FX swap), STABLECOIN_MINT/BURN (bridge)
  rail_health.rb    RailHealth enum (HEALTHY, DEGRADED, CIRCUIT_OPEN)
  account_node.rb   AccountNode T::Struct (immutable)
  rail_edge.rb      RailEdge T::Struct + fee/latency/cutoff math
  transfer_intent.rb    TransferIntent T::Struct (one instruction)
  bilateral_netter.rb   Stage 2: corridor grouping + cancellation
  netting_summary.rb    Per-corridor netting outcome
  compressed_settlement.rb  The surviving net movement per corridor
  netting_result.rb     Summaries + settlements + aggregate totals
  graph.rb          Graph container: adjacency, lookups, invariants
  fixtures.rb       The 10-node / 22-rail demo network and the
                    120-instruction netting batch (match the UI)
test/               Minitest suite
```

## Design decisions

- **Integer math everywhere.** Money is integer cents, spreads are
  integer basis points, FX rates are scaled by 1e6, and latency is
  integer **milliseconds** — the starter sketch's `latency_minutes`
  would round a 22.5s stablecoin hop down to zero.
- **Enums, not symbols/strings.** `RailKind`, `RailHealth`,
  `AccountKind` and `Currency` are `T::Enum`s whose serialization
  matches the TypeScript engine (`src/types/railsmith.ts`), so the
  UI and the Ruby engine can share payloads later.
- **Three-state health.** The starter sketch's `healthy` boolean
  became `RailHealth::Healthy/Degraded/CircuitOpen`, matching the UI's
  circuit breakers and giving Stage 4 a degraded-but-routable state.
- **Fail-fast construction.** `Graph#add_edge` rejects duplicate ids,
  unknown endpoints, negative fees, out-of-range spreads/cutoffs and
  non-positive latency/rates at build time. `BilateralNetter` likewise
  rejects negative amounts and self-transfers before grouping.
- **Compression is basis points too.** Netting compression is stored
  as integer bps (8583 = 85.83%), never a float percentage;
  `compression_pct` exists for display only.
- **Corridor strings match the UI** (`eu ↔ us · USD`), and netting is
  pure over `TransferIntent`s — no graph dependency, so compression
  runs before routing.

## Verify

```
bundle install
bundle exec srb tc   # static typecheck
bundle exec rake     # minitest suite
```

Enum/struct serialization round-trips:

```ruby
graph = RailSmith::Fixtures.demo_graph
graph.edges_from('us').map(&:total_fee_cents) # per-rail fees, integer cents
```
