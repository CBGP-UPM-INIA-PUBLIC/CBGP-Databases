# frozen_string_literal: true

# The History-database MCP server: one JSON-RPC 2.0 endpoint (POST
# /mcp/history), kept in its own file/folder from the core server
# (app/controllers/mcp/core_routes.rb) per the MCP servers plan - own tool
# registry, own bearer token. Same "def set_*_routes" pattern as
# core_routes.rb/routes.rb.
#
# /mcp/history is added to routes.rb's public_paths allowlist (own
# bearer-token auth here, not session-based).
HISTORY_MCP_TOOLS = [
  McpTools::History::RecordHistory,
  McpTools::History::RecordTimeline,
  McpTools::History::TemporalSearch,
  McpTools::History::AggregateOverTime,
  McpTools::History::PointInTimeSnapshot,
  McpTools::History::InstituteTimeline,
  McpTools::Shared::ComputeStatistics,
  McpTools::Shared::RenderChart
].freeze

def set_history_mcp_routes
  before '/mcp/history' do
    unless CBGP::McpAuth.authorized?(request.env['HTTP_AUTHORIZATION'], ENV['HISTORY_MCP_TOKEN'])
      halt 401, { error: 'Unauthorized' }.to_json
    end
  end

  post '/mcp/history' do
    content_type :json
    body = CBGP::McpDispatch.handle(server_name: 'cbgp-history-mcp', tool_classes: HISTORY_MCP_TOOLS,
                                     request_body: request.body.read)
    halt 202, '' if body.empty? # notifications/initialized - no response body
    body
  end
end
