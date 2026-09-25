# frozen_string_literal: true

require 'rack/test'
require_relative '../app/controllers/application_controller'

# End-to-end coverage of the real /mcp/history endpoint (app/controllers/mcp/
# history_routes.rb) - same pattern as spec/mcp_core_routes_spec.rb.
RSpec.describe '/mcp/history', type: :request do
  include Rack::Test::Methods

  def app
    CBGP::DatabasesApp
  end

  around do |example|
    original = ENV.fetch('HISTORY_MCP_TOKEN', nil)
    ENV['HISTORY_MCP_TOKEN'] = 'test-history-token'
    example.run
    ENV['HISTORY_MCP_TOKEN'] = original
  end

  def rpc(method, params = nil, token: 'test-history-token')
    header 'Authorization', "Bearer #{token}" if token
    header 'Content-Type', 'application/json'
    body = { jsonrpc: '2.0', id: 1, method: method }
    body[:params] = params if params
    post '/mcp/history', body.to_json
  end

  it 'rejects a request with no Authorization header' do
    rpc('tools/list', nil, token: nil)
    expect(last_response.status).to eq(401)
  end

  it 'rejects a request with the wrong token (and the core token does not also work here)' do
    rpc('tools/list', nil, token: 'test-core-token')
    expect(last_response.status).to eq(401)
  end

  it 'answers tools/list with the full history tool registry when the token matches' do
    rpc('tools/list')
    expect(last_response.status).to eq(200)

    body = JSON.parse(last_response.body)
    names = body['result']['tools'].map { |t| t['name'] }
    expect(names).to include('record_history', 'record_timeline', 'temporal_search', 'aggregate_over_time',
                              'point_in_time_snapshot', 'institute_timeline', 'compute_statistics', 'render_chart',
                              'funder_lookup')
  end

  it 'calls record_history end-to-end, with the underlying DB functions stubbed' do
    allow(McpTools::History::RecordHistory).to receive(:find_primary_id)
      .with(hash_including(form_type: 'member', questionclass: 'member_orcid', value: '0000-0001'))
      .and_return('m1')
    allow(McpTools::History::RecordHistory).to receive(:full_timeline)
      .with(hash_including(form_type: 'member', primary_id: 'm1'))
      .and_return([{ graph_uri: 'g1', generated_at: '2023-01-01T00:00:00Z', invalidated_at: nil,
                      reason: nil, detail: nil, triples: [] }])

    rpc('tools/call', { name: 'record_history',
                         arguments: { form_type: 'member', questionclass: 'member_orcid', value: '0000-0001' } })

    body = JSON.parse(last_response.body)
    content = JSON.parse(body['result']['content'].first['text'])
    expect(content['primary_id']).to eq('m1')
    expect(content['timeline'].size).to eq(1)
  end

  it 'turns a real tool error into a JSON-RPC error rather than a 500' do
    allow(McpTools::History::RecordHistory).to receive(:find_primary_id).and_return(nil)

    rpc('tools/call', { name: 'record_history',
                         arguments: { form_type: 'member', questionclass: 'member_orcid', value: 'nope' } })

    expect(last_response.status).to eq(200) # JSON-RPC errors are still HTTP 200
    body = JSON.parse(last_response.body)
    expect(body['error']['code']).to eq(-32_000)
    expect(body['error']['message']).to include('No member record found')
  end
end
