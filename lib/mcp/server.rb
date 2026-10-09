# frozen_string_literal: true

require 'json'
require_relative 'tool'
require_relative 'instructions'
require_relative 'catalog'

module Mcp
  # JSON-RPC 2.0 dispatch for the Model Context Protocol over Streamable HTTP
  # (plain request/response: every request is answered with one JSON
  # document, notifications with nothing). Hand-rolled on purpose: the
  # protocol surface we need is five methods, and owning it means the exact
  # shape of every response is visible in this one file.
  module Server
    SUPPORTED_VERSIONS = %w[2025-06-18 2025-03-26 2024-11-05].freeze
    SERVER_INFO = { name: 'cbgp-databases', version: '1' }.freeze

    PARSE_ERROR = -32_700
    INVALID_REQUEST = -32_600
    METHOD_NOT_FOUND = -32_601
    INVALID_PARAMS = -32_602

    module_function

    # @param payload [Object] the parsed JSON body (Hash, or Array for a batch)
    # @return [Hash, Array, nil] the response document; nil when nothing is
    #   to be sent back (notifications only)
    def handle(payload)
      return handle_batch(payload) if payload.is_a?(Array)
      return error_response(nil, INVALID_REQUEST, 'Request must be a JSON object') unless payload.is_a?(Hash)

      handle_one(payload)
    end

    def handle_batch(payloads)
      return error_response(nil, INVALID_REQUEST, 'Empty batch') if payloads.empty?

      responses = payloads.filter_map { |p| p.is_a?(Hash) ? handle_one(p) : error_response(nil, INVALID_REQUEST, 'Invalid request') }
      responses.empty? ? nil : responses
    end

    def handle_one(message)
      id = message['id']
      method = message['method']
      notification = !message.key?('id')
      return error_response(id, INVALID_REQUEST, 'Missing method') unless method.is_a?(String)
      return nil if notification # notifications/initialized, notifications/cancelled...

      params = message['params'].is_a?(Hash) ? message['params'] : {}
      case method
      when 'initialize' then result_response(id, initialize_result(params))
      when 'ping' then result_response(id, {})
      when 'tools/list' then result_response(id, tools: Tool.registry.map(&:definition))
      when 'tools/call' then call_tool(id, params)
      else error_response(id, METHOD_NOT_FOUND, "Method not found: #{method}")
      end
    end

    def initialize_result(params)
      requested = params['protocolVersion'].to_s
      {
        protocolVersion: SUPPORTED_VERSIONS.include?(requested) ? requested : SUPPORTED_VERSIONS.first,
        capabilities: { tools: { listChanged: false } },
        serverInfo: SERVER_INFO,
        instructions: Mcp::Catalog.instructions
      }
    end

    # A tool problem is reported as a normal result flagged isError (so the
    # model reads the message and corrects itself), not as a protocol error.
    def call_tool(id, params)
      tool = Tool.find(params['name'].to_s)
      unless tool
        names = Tool.registry.map(&:tool_name).join(', ')
        return result_response(id, tool_failure("Unknown tool '#{params['name']}'. Available tools: #{names}."))
      end

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      content = tool.invoke(params['arguments'])
      # Names only: arguments can carry personal data and must not reach logs.
      warn format('[MCP] %<tool>s ok %<ms>dms', tool: tool.tool_name, ms: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000)
      result_response(id, content: content, isError: false)
    rescue ToolError, ArgumentError => e
      warn "[MCP] #{params['name']} rejected: #{e.message}"
      result_response(id, tool_failure(e.message))
    rescue StandardError => e
      warn "[MCP] #{params['name']} failed: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      result_response(id, tool_failure('The tool failed unexpectedly on the server. Try again once; if it fails again, ' \
                                       'tell the user the data service has a problem and do not guess an answer.'))
    end

    def tool_failure(message)
      { content: [{ type: 'text', text: "Error: #{message}" }], isError: true }
    end

    def result_response(id, result)
      { jsonrpc: '2.0', id: id, result: result }
    end

    def error_response(id, code, message)
      { jsonrpc: '2.0', id: id, error: { code: code, message: message } }
    end
  end
end
