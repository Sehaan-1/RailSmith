# frozen_string_literal: true
# typed: true

require 'test_helper'
require 'railsmith/api'
require 'net/http'
require 'json'

class ApiTest < Minitest::Test
  def setup
    @server = RailSmith::ApiServer.new(port: 0)
    @thread = Thread.new { @server.start }
    @base = "http://127.0.0.1:#{@server.port}"
  end

  def teardown
    @server.stop
    @thread.join(2)
    @thread.kill if @thread.alive?
  end

  def get(path)
    Net::HTTP.get_response(URI("#{@base}#{path}"))
  end

  def post(path, body)
    Net::HTTP.post(URI("#{@base}#{path}"), JSON.generate(body), 'Content-Type' => 'application/json')
  end

  def test_health_probe
    data = JSON.parse(get('/api/health').body)
    assert data['ok']
    assert_match 'railsmith-ruby', data['engine']
  end

  def test_graph_shape
    data = JSON.parse(get('/api/graph').body)
    assert_equal 10, data['nodes'].size
    assert_equal 22, data['edges'].size
    mint = data['edges'].find { |e| e['id'] == 'mint' }
    assert_equal 'STABLECOIN_MINT', mint['railKind']
    assert_in_delta 0.375, mint['latencyMinutes'], 0.0001
    assert_equal 'HEALTHY', mint['health']
  end

  def test_route_matches_engine
    data = JSON.parse(post('/api/route', {
      sourceNodeId: 'us', targetNodeId: 'eu', amountCents: 2_500_000, hourUtc: 10, speedWeight: 0.15
    }).body)
    assert_equal %w[ach fx-sepa], data['optimal']['pathEdges'].map { |e| e['id'] }
    assert_equal 3_050, data['optimal']['totalFeeCents']
    assert_in_delta 1040.0, data['optimal']['estimatedMinutes'], 0.0001
    assert_equal '12 bps', data['optimal']['effectiveRateDisplay']
    assert_empty data['exclusions']
  end

  def test_route_with_health_overlay_reroutes
    edges = RailSmith::Fixtures.edges.map do |e|
      {
        id: e.id, fromNodeId: e.from_node, toNodeId: e.to_node, railKind: e.rail_kind.serialize,
        fixedFeeCents: e.fixed_fee_cents, spreadBps: e.spread_bps, latencyMinutes: e.latency_minutes,
        cutoffHourUtc: e.cutoff_hour_utc, health: e.id == 'fx-sepa' ? 'CIRCUIT_OPEN' : 'HEALTHY'
      }
    end
    data = JSON.parse(post('/api/route', {
      sourceNodeId: 'us', targetNodeId: 'eu', amountCents: 2_500_000, hourUtc: 10, speedWeight: 0.15, edges: edges
    }).body)
    assert_equal %w[ach fx-gb gb-eu], data['optimal']['pathEdges'].map { |e| e['id'] }
    assert_equal 'CIRCUIT_OPEN', data['exclusions'].find { |x| x['edgeId'] == 'fx-sepa' }['reason']
  end

  def test_net
    data = JSON.parse(post('/api/net', {
      transfers: [
        { id: 't1', sourceNodeId: 'us', targetNodeId: 'eu', amountCents: 10_000_000, currency: 'USD' },
        { id: 't2', sourceNodeId: 'eu', targetNodeId: 'us', amountCents: 7_000_000, currency: 'USD' }
      ]
    }).body)
    assert_equal 1, data['summaries'].size
    assert_equal 3_000_000, data['summaries'].first['nettedMovementCents']
    assert_in_delta 82.35, data['summaries'].first['compressionPct'], 0.01
    assert_equal 3_000_000, data['settlements'].first['amountCents']
    assert_equal 14_000_000, data['totals']['savedVolumeCents']
  end

  def test_ledger
    data = JSON.parse(post('/api/ledger', {
      id: 'tr-1', sourceNodeId: 'us', targetNodeId: 'eu', amountCents: 2_500_000,
      currency: 'USD', edgeIds: %w[ach fx-sepa]
    }).body)
    assert_equal 4, data['postings'].size
    assert_equal 'tr-1:ach:debit', data['postings'].first['id']
    assert data['balanced']
    assert_equal({ 'USD' => { 'debit' => 5_000_000, 'credit' => 5_000_000 } }, data['totals'])
  end

  def test_bad_requests_get_400
    assert_equal '400', post('/api/route', { sourceNodeId: 'us' }).code
    assert_equal '400', post('/api/ledger', {
      id: 'x', sourceNodeId: 'us', targetNodeId: 'eu', amountCents: 1, currency: 'USD', edgeIds: ['nope']
    }).code
    assert_equal '400', post('/api/net', {
      transfers: [{ id: 't', sourceNodeId: 'a', targetNodeId: 'b', amountCents: 1, currency: 'NOPE' }]
    }).code
    assert_equal '405', get('/api/route').code
  end
end
