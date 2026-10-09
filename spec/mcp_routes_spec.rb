# frozen_string_literal: true

require 'rack/test'
require_relative '../app/controllers/application_controller'

# POST /mcp: the HTTP face of the MCP layer. Outside the session login, guarded
# by a bearer token that fails closed.
RSpec.describe 'POST /mcp', type: :request do
  include Rack::Test::Methods

  def app
    CBGP::DatabasesApp
  end

  def rpc(body, token: 'secret')
    header 'Host', 'localhost'
    header 'Authorization', "Bearer #{token}" if token
    post '/mcp', body.is_a?(String) ? body : JSON.generate(body), 'CONTENT_TYPE' => 'application/json'
  end

  let(:ping) { { jsonrpc: '2.0', id: 7, method: 'ping' } }

  context 'with MCP_TOKEN configured' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('MCP_TOKEN').and_return('secret')
    end

    it 'answers a JSON-RPC request for a caller with the token, with no browser session' do
      rpc(ping)
      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')
      expect(JSON.parse(last_response.body)).to eq('jsonrpc' => '2.0', 'id' => 7, 'result' => {})
    end

    it 'lists the tools over HTTP' do
      rpc({ jsonrpc: '2.0', id: 1, method: 'tools/list' })
      names = JSON.parse(last_response.body).dig('result', 'tools').map { |t| t['name'] }
      expect(names).to include('describe_form', 'search_records', 'get_record', 'linked_records', 'record_history', 'render_timeline')
    end

    it 'refuses a wrong token and a missing one' do
      rpc(ping, token: 'wrong')
      expect(last_response.status).to eq(401)
      rpc(ping, token: nil)
      expect(last_response.status).to eq(401)
    end

    it 'acknowledges a notification with 202 and no body' do
      rpc({ jsonrpc: '2.0', method: 'notifications/initialized' })
      expect(last_response.status).to eq(202)
      expect(last_response.body).to eq('')
    end

    it 'answers invalid JSON with a JSON-RPC parse error' do
      rpc('{nope')
      expect(last_response.status).to eq(400)
      expect(JSON.parse(last_response.body).dig('error', 'code')).to eq(Mcp::Server::PARSE_ERROR)
    end

    it 'does not offer a GET stream' do
      header 'Host', 'localhost'
      get '/mcp'
      expect(last_response.status).to eq(405)
    end
  end

  context 'with MCP_TOKEN unset or blank' do
    it 'is disabled, never open' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('MCP_TOKEN').and_return('')
      rpc(ping, token: '')
      expect(last_response.status).to eq(503)
    end
  end
end
