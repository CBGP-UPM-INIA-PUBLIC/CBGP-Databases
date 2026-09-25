# frozen_string_literal: true

require 'rack/test'
require_relative '../app/controllers/application_controller'

# End-to-end coverage of the real /mcp/core endpoint (app/controllers/mcp/
# core_routes.rb): the bearer-token gate, and that a JSON-RPC call actually
# reaches a real tool through the full Sinatra stack. Mirrors the pattern
# spec/routes_active_members_spec.rb already uses for stubbing the
# top-level query functions - here on CBGP::DatabasesApp, since that's the
# implicit receiver inside a route block.
RSpec.describe '/mcp/core', type: :request do
  include Rack::Test::Methods

  def app
    CBGP::DatabasesApp
  end

  around do |example|
    original = ENV.fetch('CORE_MCP_TOKEN', nil)
    ENV['CORE_MCP_TOKEN'] = 'test-core-token'
    example.run
    ENV['CORE_MCP_TOKEN'] = original
  end

  def rpc(method, params = nil, token: 'test-core-token')
    header 'Authorization', "Bearer #{token}" if token
    header 'Content-Type', 'application/json'
    body = { jsonrpc: '2.0', id: 1, method: method }
    body[:params] = params if params
    post '/mcp/core', body.to_json
  end

  it 'rejects a request with no Authorization header' do
    rpc('tools/list', nil, token: nil)
    expect(last_response.status).to eq(401)
  end

  it 'rejects a request with the wrong token' do
    rpc('tools/list', nil, token: 'wrong-token')
    expect(last_response.status).to eq(401)
  end

  it 'answers tools/list with the full core tool registry when the token matches' do
    rpc('tools/list')
    expect(last_response.status).to eq(200)

    body = JSON.parse(last_response.body)
    names = body['result']['tools'].map { |t| t['name'] }
    expect(names).to include('list_form_facets', 'search_records', 'get_record', 'aggregate',
                              'publication_project_heuristic_link', 'ontology_relationships',
                              'compute_statistics', 'render_chart')
  end

  it 'calls a real tool (list_form_facets) end-to-end through the JSON-RPC endpoint' do
    rpc('tools/call', { name: 'list_form_facets', arguments: { form_type: 'member' } })
    expect(last_response.status).to eq(200)

    body = JSON.parse(last_response.body)
    content = JSON.parse(body['result']['content'].first['text'])
    expect(content['form_type']).to eq('member')
    expect(content['facets']).to be_an(Array)
  end

  it 'calls search_records end-to-end, with the underlying DB functions stubbed' do
    # NOT allow_any_instance_of(CBGP::DatabasesApp) here - unlike a plain
    # route block, self inside McpTools::Core::SearchRecords.call is the
    # tool class itself, since the dispatcher calls tool_class.call(...)
    # directly rather than instance_eval-ing it into the app.
    allow(McpTools::Core::SearchRecords).to receive(:execute_search)
      .with(hash_including(dataset_type: 'member')).and_return(['urn:g1'])
    allow(McpTools::Core::SearchRecords).to receive(:fetch_datasets_raw_data)
      .with(hash_including(graph_uris: ['urn:g1'], database: 'member'))
      .and_return([{ dataset: 'urn:g1', member_name: 'Maria' }])

    rpc('tools/call', { name: 'search_records', arguments: { form_type: 'member', search_params: {} } })

    body = JSON.parse(last_response.body)
    content = JSON.parse(body['result']['content'].first['text'])
    expect(content['records'].first['@id']).to eq('urn:g1')
  end
end
