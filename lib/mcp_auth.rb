# frozen_string_literal: true

module CBGP
  # Trivial bearer-token gate for an MCP endpoint - the whole auth story is
  # "does this one shared secret match", deliberately: these endpoints only
  # ever run behind the institute firewall/VPN, so a heavier scheme (OAuth,
  # per-user accounts) would be complexity without a matching threat to
  # justify it. Still a real check, in case a future compose/network change
  # ever exposes the port further than intended.
  module McpAuth
    # @param authorization_header [String, nil] the raw "Authorization" header
    # @param token [String, nil] the expected token (an env var, usually) -
    #   deliberately fails closed (returns false) if this is blank, so a
    #   missing/unset token env var can never mean "no auth required"
    # @return [Boolean]
    def self.authorized?(authorization_header, token)
      return false if token.to_s.empty?

      authorization_header == "Bearer #{token}"
    end
  end
end
