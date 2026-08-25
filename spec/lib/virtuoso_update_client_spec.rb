# frozen_string_literal: true

# Covers CBGP::VirtuosoUpdateClient, added when this project switched from
# GraphDB to Virtuoso (2026-08-25) - GraphDB's return to requiring periodic
# re-registration even for its free tier was the trigger. Virtuoso's SPARQL
# Update endpoint (/sparql-auth) requires HTTP Digest auth and rejects Basic
# outright; the sparql-client gem has no Digest support, so this small class
# exists purely to cover the write path (reads stay on plain SPARQL::Client
# against Virtuoso's unauthenticated /sparql endpoint - unaffected).
RSpec.describe CBGP::VirtuosoUpdateClient do
  subject(:client) do
    described_class.new(endpoint: 'http://localhost:8890/sparql-auth', user: 'dba', password: 'secret')
  end

  let(:http) { instance_double(Net::HTTP) }
  let(:challenge) do
    instance_double(Net::HTTPUnauthorized, code: '401',
                                            '[]': 'Digest realm="SPARQL", nonce="abc123", qop="auth", algorithm="MD5"')
  end
  let(:success) { instance_double(Net::HTTPOK, code: '200', message: 'OK', body: '') }

  before do
    allow(Net::HTTP).to receive(:new).with('localhost', 8890).and_return(http)
    allow(success).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    allow(challenge).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
  end

  describe '#update' do
    it 'probes for the digest challenge, then resends with a computed Authorization header' do
      allow(http).to receive(:request).and_return(challenge, success)

      client.update('INSERT DATA { <urn:s> <urn:p> "v" }')

      expect(http).to have_received(:request).twice
    end

    it 'sends the query as the "update" form field on both requests' do
      sent_requests = []
      allow(http).to receive(:request) do |req|
        sent_requests << req
        sent_requests.size == 1 ? challenge : success
      end

      client.update('INSERT DATA { <urn:s> <urn:p> "v" }')

      expect(sent_requests.size).to eq(2)
      sent_requests.each do |req|
        expect(req.body).to include('update=')
      end
    end

    it 'includes a computed Authorization header only on the second request' do
      sent_requests = []
      allow(http).to receive(:request) do |req|
        sent_requests << req
        sent_requests.size == 1 ? challenge : success
      end

      client.update('INSERT DATA { <urn:s> <urn:p> "v" }')

      expect(sent_requests.first['Authorization']).to be_nil
      expect(sent_requests.last['Authorization']).to match(/^Digest /)
    end

    it 'raises with a clear message when Virtuoso does not challenge as expected' do
      allow(http).to receive(:request).and_return(success)

      expect { client.update('INSERT DATA { <urn:s> <urn:p> "v" }') }
        .to raise_error(/did not challenge for auth/)
    end

    it 'raises with the response body when the authenticated request still fails' do
      failure = instance_double(Net::HTTPForbidden, code: '403', message: 'Forbidden', body: 'no permission')
      allow(failure).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      allow(http).to receive(:request).and_return(challenge, failure)

      expect { client.update('INSERT DATA { <urn:s> <urn:p> "v" }') }
        .to raise_error(/403 Forbidden.*no permission/m)
    end
  end

  describe '#insert_data' do
    it 'serializes the given RDF data into an INSERT DATA GRAPH block and sends it through #update' do
      graph = RDF::Graph.new do |g|
        g << [RDF::URI('http://example.org/s'), RDF::URI('http://example.org/p'), 'v']
      end

      sent_requests = []
      allow(http).to receive(:request) do |req|
        sent_requests << req
        sent_requests.size == 1 ? challenge : success
      end

      client.insert_data(graph, graph: 'http://example.org/testgraph')

      body = CGI.unescape(sent_requests.last.body)
      expect(body).to include('INSERT DATA')
      expect(body).to include('GRAPH <http://example.org/testgraph>')
      expect(body).to include('<http://example.org/s> <http://example.org/p> "v"')
    end
  end
end
