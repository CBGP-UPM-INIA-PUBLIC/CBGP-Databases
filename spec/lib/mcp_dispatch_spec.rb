# frozen_string_literal: true

# CBGP::McpDispatch (lib/mcp_dispatch.rb) - the shared JSON-RPC 2.0 handling
# both MCP endpoints (app/controllers/mcp/core_routes.rb,
# app/controllers/mcp/history_routes.rb) sit on top of. Tested here against
# a fake tool class, independent of either endpoint's real tool list, so
# these pin the protocol-handling behavior itself.
RSpec.describe CBGP::McpDispatch do
  let(:tool_class) do
    Class.new do
      const_set(:NAME, 'fake_tool')
      const_set(:DESCRIPTION, 'does a fake thing')
      const_set(:INPUT_SCHEMA, { type: 'object', properties: { x: { type: 'string' } }, required: ['x'] })

      def self.call(arguments)
        [{ type: 'text', text: "got #{arguments['x']}" }]
      end
    end
  end

  def handle(method, params = nil, id = 1)
    body = { jsonrpc: '2.0', id: id, method: method }
    body[:params] = params if params
    JSON.parse(described_class.handle(server_name: 'test-server', tool_classes: [tool_class], request_body: body.to_json))
  end

  it 'answers initialize with protocol info and the given server name' do
    response = handle('initialize')
    expect(response['result']['protocolVersion']).to eq(described_class::PROTOCOL_VERSION)
    expect(response['result']['serverInfo']['name']).to eq('test-server')
  end

  it 'lists tools derived from the tool class constants, never hand-duplicated' do
    response = handle('tools/list')
    tool = response['result']['tools'].first
    expect(tool['name']).to eq('fake_tool')
    expect(tool['description']).to eq('does a fake thing')
    expect(tool['inputSchema']['required']).to eq(['x'])
  end

  it 'dispatches tools/call to the matching tool class and wraps the result as content' do
    response = handle('tools/call', { name: 'fake_tool', arguments: { x: 'hello' } })
    expect(response['result']['content']).to eq([{ 'type' => 'text', 'text' => 'got hello' }])
  end

  it 'returns a JSON-RPC error, not a crash, for an unknown tool name' do
    response = handle('tools/call', { name: 'nonexistent', arguments: {} })
    expect(response['error']['code']).to eq(-32_602)
  end

  it 'returns a JSON-RPC error for an unknown method' do
    response = handle('not/a/real/method')
    expect(response['error']['code']).to eq(-32_601)
  end

  it 'turns any exception a tool raises into a JSON-RPC error rather than propagating it' do
    exploding_tool = Class.new do
      const_set(:NAME, 'exploding_tool')
      const_set(:DESCRIPTION, 'always fails')
      const_set(:INPUT_SCHEMA, { type: 'object', properties: {}, required: [] })

      def self.call(_arguments)
        raise ArgumentError, 'bad input'
      end
    end

    response = JSON.parse(described_class.handle(
                             server_name: 'test-server', tool_classes: [exploding_tool],
                             request_body: { jsonrpc: '2.0', id: 1, method: 'tools/call',
                                              params: { name: 'exploding_tool', arguments: {} } }.to_json
                           ))
    expect(response['error']['code']).to eq(-32_000)
    expect(response['error']['message']).to include('bad input')
  end

  it 'preserves the request id (including string ids) on both success and error responses' do
    expect(handle('tools/list', nil, 'abc-123')['id']).to eq('abc-123')
    expect(handle('bogus/method', nil, 'abc-123')['id']).to eq('abc-123')
  end
end
