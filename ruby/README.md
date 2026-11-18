# RailSmith engine (Ruby + Sorbet)

A Sorbet-typed multi-rail payment & FX graph engine, modeled on the
architecture of Stripe's Global Payments and Treasury Network
(GPTN). Accounts, treasury FX hubs and stablecoin wallets are nodes;
payment corridors (ACH, SEPA, wire, FX swap, stablecoin mint/burn)
are directed, weighted edges with fixed fees, basis-point spreads,
settlement latency and daily cutoff windows.

All four planned stages are implemented:

1. **Typed graph schema** (done) — `AccountNode` / `RailEdge` structs, enums,
   and a `Graph` container that validates corridor invariants up front.
2. **Flow compression** (done) — `BilateralNetter` cancels opposing
   obligations per corridor before any transfer touches an external bank.
3. **Cost vs. speed routing** (done) — `GraphRouter` runs constrained
   Dijkstra over a composite edge weight
   (`fee_cents + latency_minutes * speed_weight * 10`), from
   cost-first multi-hop FX to hybrid fiat → stablecoin bridges, with
   cutoff/circuit-breaker exclusions and a runner-up failover quote.
4. **Resilience & reconciliation** (done) — `CircuitBreaker` tracks
   live error rates per rail and trips/restores circuits so routing
   fails over automatically; `LedgerGenerator` emits frozen, balanced
   double-entry records per hop.

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
  graph_router.rb   Stage 3: constrained Dijkstra, cost vs. speed
  route_quote.rb    Priced multi-hop path (integer cents + ms)
  route_result.rb   Optimal + runner-up quotes + exclusions
  route_exclusion.rb / exclusion_reason.rb  Why a rail was skipped
  circuit_breaker.rb  Stage 4: sliding-window error rates trip circuits
  ledger_generator.rb Stage 4: frozen balanced double-entry postings
  ledger_posting.rb / posting_direction.rb  Journal records
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
- **Routing weights are scores, not money.** Dijkstra floats the
  composite weight internally, but every reported fee and latency on
  a `RouteQuote` stays integer cents / milliseconds. Quotes include
  spread fees for the queried amount (not just fixed fees).
- **Degraded rails cost double; broken ones are gone.** DEGRADED
  routes at a 2x penalty, CIRCUIT_OPEN and past-cutoff rails are
  excluded and reported on the result. The runner-up quote is the
  best route with each winning edge removed in turn — the failover
  path Stage 4 promotes.
- **Breakers trip on evidence, recover with hysteresis.** A rail's
  circuit opens when its sliding-window error rate (default: last 20
  outcomes, min 5 samples) reaches 50%, and only rails the breaker
  itself tripped are restored below 25% — an operator's manual
  circuit-open is never resurrected.
- **The ledger is frozen and proven balanced.** Postings are
  immutable debit/credit pairs per hop; the per-currency invariant
  is asserted before the journal is returned, and `balanced?` /
  `totals` expose it for reconciliation.

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

## HTTP API (optional front door)

A thin WEBrick JSON server exposes the engine to the React workbench
(`../src/ui`). It is loaded explicitly (`require 'railsmith/api'`), so
the core engine never depends on a web stack:

```
bundle exec ruby bin/railsmith-api   # listens on 0.0.0.0:8080 (PORT to override)
```

| Endpoint | Body | Returns |
| --- | --- | --- |
| `GET /api/health` | — | `{ ok, engine }` probe the UI uses to pick its engine |
| `GET /api/graph` | — | demo nodes + edges, TS field names |
| `POST /api/route` | `sourceNodeId, targetNodeId, amountCents, hourUtc, speedWeight, edges?` | `{ optimal, runnerUp, exclusions }` |
| `POST /api/net` | `transfers[]` | `{ summaries, settlements, totals }` |
| `POST /api/ledger` | `id, sourceNodeId, targetNodeId, amountCents, currency, edgeIds[]` | `{ postings, balanced, totals }` |

The API is stateless: `/api/route` accepts the caller's current rail
health as an edge overlay and validates it through the Stage 1 graph
invariants, so UI and engine can never drift apart. Field names and
enum serializations are the TypeScript ones (`DEBIT`, `HEALTHY`,
`eu ↔ us · USD`), so the UI falls back to its bundled TS engine
without any mapping layer. With the Vite dev server running, `/api`
is proxied to port 8080 automatically — run `npm run dev` and
`npm run engine` side by side.
