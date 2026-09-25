# frozen_string_literal: true

# The core-database MCP server: one JSON-RPC 2.0 endpoint (POST /mcp/core),
# kept in its own file/folder from the History server (app/controllers/mcp/
# history_routes.rb) and from the human-facing routes.rb, per the MCP
# servers plan - two separate tool registries, two separate bearer tokens,
# easy to find independently. Same top-level "def set_*_routes, called from
# inside `class DatabasesApp < Sinatra::Base`" pattern application_controller.rb
# already uses for routes.rb, not a class reopening (Sinatra::Base subclass
# reopening doesn't fit how this app loads its route files).
#
# /mcp/core is added to routes.rb's public_paths allowlist (it has its own
# bearer-token auth here, not session-based - MCP clients don't have
# cookies).
CORE_MCP_TOOLS = [
  McpTools::Core::ListFormFacets,
  McpTools::Core::OntologyRelationships,
  McpTools::Core::SearchRecords,
  McpTools::Core::GetRecord,
  McpTools::Core::Aggregate,
  McpTools::Core::PublicationProjectHeuristicLink,
  McpTools::Shared::ComputeStatistics,
  McpTools::Shared::RenderChart,
  McpTools::Shared::FunderLookup
].freeze

def set_core_mcp_routes
  before '/mcp/core' do
    unless CBGP::McpAuth.authorized?(request.env['HTTP_AUTHORIZATION'], ENV['CORE_MCP_TOKEN'])
      halt 401, { error: 'Unauthorized' }.to_json
    end
  end

  post '/mcp/core' do
    content_type :json
    body = CBGP::McpDispatch.handle(server_name: 'cbgp-core-mcp', tool_classes: CORE_MCP_TOOLS,
                                     request_body: request.body.read)
    halt 202, '' if body.empty? # notifications/initialized - no response body
    body
  end
end
