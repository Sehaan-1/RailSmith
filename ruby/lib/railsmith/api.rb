# frozen_string_literal: true
# typed: false

require 'json'
require 'webrick'

module RailSmith
  # JSON-over-HTTP front door to the engine, so the React workbench
  # can run against the Ruby implementation instead of its bundled
  # TypeScript one.
  #
  #   GET  /api/health    probe used by the UI to pick its engine
  #   GET  /api/graph     the demo network, TS field names
  #   POST /api/route     sourceNodeId, targetNodeId, amountCents,
  #                       hourUtc, speedWeight, edges[] overlay (optional)
  #   POST /api/net       transfers[]
  #   POST /api/ledger    id, sourceNodeId, targetNodeId, amountCents,
  #                       currency, edgeIds[]
  #   POST /api/circuit-breaker outcomes[] (edgeId, failed)
  #
  # Stateless by design: a routing request carries the caller's
  # current view of rail health as an edge overlay, validated through
  # the Stage 1 graph invariants — no shared mutable server state, no
  # drift between UI and engine.
  #
  # This file is the untyped boundary: WEBrick ships no RBI, so the
  # engine core stays `typed: strict` and this shell is `typed: false`.
  # It is required explicitly (`require 'railsmith/api'`), so the core
  # engine loads without the webrick dependency.
  class ApiServer
    def initialize(port: 8080)
      @server = WEBrick::HTTPServer.new(
        Port: port,
        BindAddress: '0.0.0.0',
        Logger: WEBrick::Log.new(File::NULL),
        AccessLog: []
      )
      mount_routes
    end

    # The actual bound port (useful when started with port: 0).
    def port
      @server.listeners.first.addr[1]
    end

    def start
      @server.start
    end

    def stop
      @server.shutdown
    end

    private

    def mount_routes
      @server.mount_proc('/api/health') do |_req, res|
        respond(res, 200, ok: true, engine: "railsmith-ruby #{RailSmith::VERSION}")
      end
      @server.mount_proc('/api/graph') { |_req, res| respond(res, 200, graph_json) }
      @server.mount_proc('/api/route') { |req, res| handle(req, res) { |body| route_json(body) } }
      @server.mount_proc('/api/net') { |req, res| handle(req, res) { |body| net_json(body) } }
      @server.mount_proc('/api/ledger') { |req, res| handle(req, res) { |body| ledger_json(body) } }
      @server.mount_proc('/api/circuit-breaker') { |req, res| handle(req, res) { |body| circuit_breaker_json(body) } }
    end

    def handle(req, res)
      unless req.request_method == 'POST'
        respond(res, 405, error: 'POST required')
        return
      end

      respond(res, 200, yield(JSON.parse(req.body || '{}')))
    rescue JSON::ParserError => e
      respond(res, 400, error: "invalid JSON: #{e.message}")
    rescue ArgumentError, KeyError, TypeError, RuntimeError => e
      respond(res, 400, error: e.message)
    end

    def respond(res, status, payload)
      res.status = status
      res['Content-Type'] = 'application/json'
      res['Access-Control-Allow-Origin'] = '*'
      res.body = JSON.generate(payload)
    end

    # ---------- handlers ----------

    def graph_json
      graph = Fixtures.demo_graph
      {
        nodes: graph.nodes.map do |node|
          { id: node.id, label: node.label, currency: node.currency.serialize, kind: node.kind.serialize, region: node.region }
        end,
        edges: graph.edges.map { |edge| edge_json(edge) }
      }
    end

    def route_json(params)
      edges = params['edges'] ? params['edges'].map { |data| edge_from_json(data) } : Fixtures.edges
      graph = Graph.new(nodes: Fixtures.nodes, edges: edges)
      result = GraphRouter.new(graph).route(
        source: params.fetch('sourceNodeId'),
        target: params.fetch('targetNodeId'),
        amount_cents: params.fetch('amountCents'),
        hour_utc: params.fetch('hourUtc'),
        speed_weight: params.fetch('speedWeight', 0.5)
      )
      {
        optimal: result.optimal && quote_json(result.optimal),
        runnerUp: result.runner_up && quote_json(result.runner_up),
        exclusions: result.exclusions.map { |ex| { edgeId: ex.edge_id, reason: ex.reason.serialize } }
      }
    end

    def net_json(params)
      transfers = params.fetch('transfers').map do |t|
        TransferIntent.new(
          id: t.fetch('id'),
          source_node: t.fetch('sourceNodeId'),
          target_node: t.fetch('targetNodeId'),
          amount_cents: t.fetch('amountCents'),
          currency: Currency.deserialize(t.fetch('currency'))
        )
      end
      result = BilateralNetter.net(transfers)
      {
        summaries: result.summaries.map do |s|
          {
            corridor: s.corridor,
            grossVolumeCents: s.gross_volume_cents,
            nettedMovementCents: s.netted_movement_cents,
            savedVolumeCents: s.saved_volume_cents,
            compressionPct: s.compression_pct
          }
        end,
        settlements: result.settlements.map do |s|
          {
            id: s.id, sourceNodeId: s.source_node, targetNodeId: s.target_node,
            amountCents: s.amount_cents, currency: s.currency.serialize, corridor: s.corridor
          }
        end,
        totals: {
          grossVolumeCents: result.total_gross_cents,
          nettedMovementCents: result.total_netted_cents,
          savedVolumeCents: result.total_saved_cents,
          compressionPct: result.compression_bps / 100.0
        }
      }
    end

    def circuit_breaker_json(params)
      graph = Fixtures.demo_graph
      breaker = CircuitBreaker.new

      params.fetch('outcomes').each do |outcome|
        edge_id = outcome.fetch('edgeId')
        raise ArgumentError, "unknown rail edge #{edge_id.inspect}" unless graph.edge(edge_id)

        failed = outcome.fetch('failed')
        unless failed == true || failed == false
          raise ArgumentError, "outcome for #{edge_id.inspect} must have a boolean failed value"
        end

        failed ? breaker.record_failure(edge_id) : breaker.record_success(edge_id)
        breaker.apply!(graph)
      end

      {
        openEdgeIds: breaker.apply!(graph),
        metrics: graph.edges.to_h do |edge|
          [edge.id, { sampleCount: breaker.sample_count(edge.id), errorRate: breaker.error_rate(edge.id) }]
        end
      }
    end

    def ledger_json(params)
      graph = Fixtures.demo_graph
      edges = params.fetch('edgeIds').map do |edge_id|
        graph.edge(edge_id) || raise(ArgumentError, "unknown rail edge #{edge_id.inspect}")
      end
      intent = TransferIntent.new(
        id: params.fetch('id'),
        source_node: params.fetch('sourceNodeId'),
        target_node: params.fetch('targetNodeId'),
        amount_cents: params.fetch('amountCents'),
        currency: Currency.deserialize(params.fetch('currency'))
      )
      postings = LedgerGenerator.generate(intent, edges, nodes: graph.nodes)
      {
        postings: postings.map do |p|
          {
            id: p.id, transferId: p.transfer_id, accountId: p.account_id,
            direction: p.direction.serialize, amountCents: p.amount_cents,
            currency: p.currency.serialize, railEdgeId: p.rail_edge_id
          }
        end,
        balanced: LedgerGenerator.balanced?(postings),
        totals: LedgerGenerator.totals(postings)
      }
    end

    # ---------- codec (Ruby snake_case <-> TS camelCase) ----------

    def edge_json(edge)
      {
        id: edge.id,
        fromNodeId: edge.from_node,
        toNodeId: edge.to_node,
        railKind: edge.rail_kind.serialize,
        fixedFeeCents: edge.fixed_fee_cents,
        spreadBps: edge.spread_bps,
        fxRateScaled: edge.fx_rate_scaled,
        latencyMinutes: edge.latency_minutes,
        cutoffHourUtc: edge.cutoff_hour_utc,
        health: edge.health.serialize
      }
    end

    def edge_from_json(data)
      RailEdge.new(
        id: data.fetch('id'),
        from_node: data.fetch('fromNodeId'),
        to_node: data.fetch('toNodeId'),
        rail_kind: RailKind.deserialize(data.fetch('railKind')),
        fixed_fee_cents: data.fetch('fixedFeeCents'),
        spread_bps: data.fetch('spreadBps'),
        fx_rate_scaled: data.fetch('fxRateScaled', FX_RATE_SCALE),
        latency_ms: (data.fetch('latencyMinutes') * 60_000).round,
        cutoff_hour_utc: data['cutoffHourUtc'],
        health: RailHealth.deserialize(data.fetch('health', 'HEALTHY'))
      )
    end

    def quote_json(quote)
      {
        pathEdges: quote.path_edges.map { |edge| edge_json(edge) },
        totalFeeCents: quote.total_fee_cents,
        estimatedMinutes: quote.estimated_minutes,
        effectiveRateDisplay: quote.effective_rate_display,
        hopCount: quote.hop_count,
        stablecoinBridge: quote.stablecoin_bridge?
      }
    end
  end
end
