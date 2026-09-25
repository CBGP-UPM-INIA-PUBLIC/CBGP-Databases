# frozen_string_literal: true

# CBGP::McpAuth (lib/mcp_auth.rb) - the deliberately minimal bearer-token
# gate on both MCP endpoints. The one behavior that actually matters here:
# a blank/unset expected token must never mean "let everyone in".
RSpec.describe CBGP::McpAuth do
  describe '.authorized?' do
    it 'accepts a matching bearer token' do
      expect(described_class.authorized?('Bearer secret123', 'secret123')).to be(true)
    end

    it 'rejects a non-matching token' do
      expect(described_class.authorized?('Bearer wrong', 'secret123')).to be(false)
    end

    it 'rejects a missing Authorization header' do
      expect(described_class.authorized?(nil, 'secret123')).to be(false)
    end

    it 'fails closed when the expected token is blank or unset, rather than allowing every request through' do
      expect(described_class.authorized?('Bearer anything', nil)).to be(false)
      expect(described_class.authorized?('Bearer anything', '')).to be(false)
      expect(described_class.authorized?(nil, nil)).to be(false)
    end

    it 'rejects a header missing the "Bearer " scheme prefix' do
      expect(described_class.authorized?('secret123', 'secret123')).to be(false)
    end
  end
end
