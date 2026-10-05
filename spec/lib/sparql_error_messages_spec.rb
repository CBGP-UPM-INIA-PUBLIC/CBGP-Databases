# frozen_string_literal: true

require 'socket'

# When Virtuoso rejects a query, the real reason (e.g. "SP030: Bad escape
# sequence") must reach the log. It used to be replaced by an unrelated
# Encoding::CompatibilityError, because sparql-client joins the reply (raw
# bytes) with the query text (UTF-8) to build its message, and that join fails
# as soon as either contains a non-ASCII character. Found 2026-10-05 chasing a
# crash caused by a stray quote in a search term. A tiny real HTTP server stands
# in for Virtuoso so the whole client path is exercised without one.
RSpec.describe 'readable SPARQL error messages' do
  # One-shot HTTP server answering every request with the given status/body.
  def with_fake_endpoint(status, body, content_type: 'text/plain')
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    thread = Thread.new do
      loop do
        socket = server.accept
        while (line = socket.gets) && line != "\r\n"; end # drain the request headers
        bytes = body.b
        socket.write("HTTP/1.1 #{status}\r\nContent-Type: #{content_type}\r\nContent-Length: #{bytes.bytesize}\r\nConnection: close\r\n\r\n")
        socket.write(bytes)
        socket.close
      rescue IOError, SystemCallError
        break
      end
    end
    yield "http://127.0.0.1:#{port}/sparql"
  ensure
    thread&.kill
    server&.close
  end

  it 'passes Virtuoso\'s own message through for a malformed query, even when it and the query are non-ASCII' do
    with_fake_endpoint('400 Bad Request', "Virtuoso 37000 Error SP030: línea 3 — Bad escape sequence in «x»") do |url|
      client = CBGP::SparqlClient.new(url)
      expect { client.query('SELECT * WHERE { ?s ?p "ñandú" }') }
        .to raise_error(SPARQL::Client::MalformedQuery) { |e|
          expect(e.message).to include('SP030', 'línea 3', 'Bad escape sequence')
          expect(e.message).to include('ñandú') # the query it was processing
        }
    end
  end

  it 'does the same for a server error' do
    with_fake_endpoint('500 Internal Server Error', 'Virtuoso 42000 Error: out of memory — ñ') do |url|
      expect { CBGP::SparqlClient.new(url).query('SELECT * WHERE { ?s ?p ?o } # ñ') }
        .to raise_error(SPARQL::Client::ServerError, /out of memory — ñ/)
    end
  end

  it 'still raises the ordinary error for plain ASCII' do
    with_fake_endpoint('400 Bad Request', 'syntax error near "}"') do |url|
      expect { CBGP::SparqlClient.new(url).query('SELECT') }.to raise_error(SPARQL::Client::MalformedQuery, /syntax error near/)
    end
  end

  it 'leaves a successful reply alone' do
    json = '{"head":{"vars":["s"]},"results":{"bindings":[{"s":{"type":"literal","value":"año"}}]}}'
    with_fake_endpoint('200 OK', json, content_type: 'application/sparql-results+json') do |url|
      client = CBGP::SparqlClient.new(url, headers: { 'Accept' => 'application/sparql-results+json' })
      expect(client.query('SELECT ?s WHERE { ?x ?y ?s }').map { |r| r[:s].to_s }).to eq(['año'])
    end
  end

  describe 'CBGP.readable_http_body' do
    it 'returns valid UTF-8 for raw bytes' do
      raw = 'línea — «x»'.b
      expect(raw.encoding).to eq(Encoding::ASCII_8BIT)
      out = CBGP.readable_http_body(raw)
      expect(out.encoding).to eq(Encoding::UTF_8)
      expect(out).to eq('línea — «x»')
      expect { 'ñ' + out }.not_to raise_error
    end

    it 'replaces bytes that are not valid UTF-8 instead of raising' do
      expect(CBGP.readable_http_body("ok \xFF\xFE bad".b)).to eq('ok ?? bad')
    end

    it 'handles nil' do
      expect(CBGP.readable_http_body(nil)).to eq('')
    end
  end

  it 'the application\'s read clients use the readable client' do
    expect(DATABASE).to be_a(CBGP::SparqlClient)
    expect(HISTORY_DATABASE).to be_a(CBGP::SparqlClient)
  end
end
