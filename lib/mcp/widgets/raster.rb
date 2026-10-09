# frozen_string_literal: true

require 'open3'
require 'timeout'

module Mcp
  module Widgets
    # SVG -> PNG with the rsvg-convert program (package librsvg2-bin; the
    # Docker image installs it, with a font). When it is not installed, or
    # fails, the answer is nil and the caller simply goes without a PNG: a
    # picture is never worth failing a tool call for.
    module Raster
      COMMAND = 'rsvg-convert'
      WIDTH_PX = 1920 # twice the drawing's own width, so it stays sharp on a slide
      TIMEOUT_SECONDS = 15

      module_function

      # @param svg [String] a standalone SVG document
      # @return [String, nil] the PNG bytes, or nil if it could not be made
      def png(svg, width: WIDTH_PX)
        stdout, stderr, status = Timeout.timeout(TIMEOUT_SECONDS) do
          Open3.capture3(COMMAND, '--format=png', "--width=#{width}", '--background-color=white', stdin_data: svg, binmode: true)
        end
        return stdout if status.success? && stdout.start_with?("\x89PNG".b)

        warn "[MCP] #{COMMAND} failed (exit #{status.exitstatus}): #{stderr.to_s.strip[0, 200]}"
        nil
      rescue Errno::ENOENT
        warn "[MCP] #{COMMAND} is not installed: no PNG (install librsvg2-bin)"
        nil
      rescue Timeout::Error, SystemCallError => e
        warn "[MCP] #{COMMAND} did not finish (#{e.class})"
        nil
      end
    end
  end
end
