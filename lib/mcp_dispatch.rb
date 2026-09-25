# frozen_string_literal: true

require 'json'

module CBGP
  # Generic JSON-RPC 2.0 dispatcher for an MCP "Streamable HTTP" endpoint -
  # no MCP SDK, following the same hand-rolled pattern already proven in the
  # FLAIR-GG VP project (app/controllers/mcp_routes.rb there): plain
  # JSON-RPC over one POST endpoint, initialize/tools-list/tools-call, each
  # tool a small class with its own NAME/DESCRIPTION/INPUT_SCHEMA constants
  # and a self.call(arguments) method. Both CBGP MCP endpoints
  # (app/controllers/mcp/core_routes.rb, app/controllers/mcp/history_routes.rb)
  # share this instead of each hand-rolling its own copy of that dispatch
  # logic; each only supplies its own server name and tool-class list.
  module McpDispatch
    PROTOCOL_VERSION = '2025-06-18'

    # tools/list result entries, always derived from the tool classes
    # themselves so this metadata can never drift out of sync with the
    # tools it describes.
    #
    # @param tool_classes [Array<Class>]
    # @return [Array<Hash>]
    def self.tool_list(tool_classes)
      tool_classes.map do |tool_class|
        { name: tool_class::NAME, description: tool_class::DESCRIPTION, inputSchema: tool_class::INPUT_SCHEMA }
      end
    end

    # @param server_name [String] reported in the "initialize" response
    # @param tool_classes [Array<Class>] each must expose NAME, DESCRIPTION,
    #   INPUT_SCHEMA constants and a self.call(arguments) class method - see
    #   lib/mcp_tools/core/*.rb / lib/mcp_tools/history/*.rb for the shape.
    # @param request_body [String] the raw POST body (a JSON-RPC request)
    # @return [String] JSON-RPC response body, or '' for a notification
    #   (the caller is responsible for returning HTTP 202 with no body then)
    def self.handle(server_name:, tool_classes:, request_body:)
      request = JSON.parse(request_body)
      id = request['id']
      method_name = request['method']
      params = request['params'] || {}

      case method_name
      when 'initialize'
        result(id, {
          protocolVersion: PROTOCOL_VERSION,
          capabilities: { tools: {} },
          serverInfo: { name: server_name, version: '1.0.0' }
        }.to_json)
      when 'notifications/initialized'
        ''
      when 'tools/list'
        result(id, { tools: tool_list(tool_classes) }.to_json)
      when 'tools/call'
        call_tool(id: id, params: params, tool_classes: tool_classes)
      else
        error(id, -32_601, "Method not found: #{method_name}")
      end
    rescue JSON::ParserError => e
      error(nil, -32_700, "Parse error: #{e.message}")
    end

    # Dispatches a tools/call request to the named tool's #call method and
    # wraps the result as MCP tool-call content. Any exception a tool raises
    # (malformed input, a rejected query, an upstream failure, ...) becomes
    # a JSON-RPC error rather than a 500 - tools are trusted to raise
    # something with a useful #message, not to catch their own errors.
    #
    # @param id [Integer, String, nil]
    # @param params [Hash] must contain "name" and an "arguments" hash
    # @param tool_classes [Array<Class>]
    # @return [String]
    def self.call_tool(id:, params:, tool_classes:)
      tool_class = tool_classes.find { |t| params['name'] == t::NAME }
      return error(id, -32_602, "Unknown tool: #{params['name']}") unless tool_class

      arguments = params['arguments'] || {}
      content = tool_class.call(arguments)
      result(id, { content: content }.to_json)
    rescue StandardError => e
      error(id, -32_000, "Tool call failed: #{e.message}")
    end
    private_class_method :call_tool

    # @param id [Integer, String, nil] the request id being answered
    # @param result_json [String] the already-serialized JSON value of "result"
    # @return [String]
    def self.result(id, result_json)
      %({"jsonrpc":"2.0","id":#{id.to_json},"result":#{result_json}})
    end

    # @param id [Integer, String, nil]
    # @param code [Integer] JSON-RPC error code
    # @param message [String]
    # @return [String]
    def self.error(id, code, message)
      %({"jsonrpc":"2.0","id":#{id.to_json},"error":{"code":#{code},"message":#{message.to_json}}})
    end
  end
end
