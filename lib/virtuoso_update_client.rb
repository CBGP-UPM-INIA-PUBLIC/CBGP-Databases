require 'net/http'
require 'net/http/digest_auth'
require 'sparql/client'

module CBGP
  # A minimal SPARQL 1.1 Update client for Virtuoso.
  #
  # Virtuoso's SPARQL Update endpoint (+/sparql-auth+) requires HTTP Digest
  # authentication and always rejects Basic auth outright (401, no retry) -
  # confirmed live against a real Virtuoso 07.20 container, along with the
  # fact that no virtuoso.ini setting in this build exposes a way to accept
  # Basic auth instead. The +sparql-client+ gem (used for reads via
  # SPARQL::Client, unaffected by any of this - Virtuoso's plain +/sparql+
  # query endpoint needs no auth) has no Digest support, so this class exists
  # purely to cover the write path: probe for the WWW-Authenticate challenge,
  # compute the digest response via the net-http-digest_auth gem, and resend.
  #
  # Exposes the same #update(query) shape DATABASE_UPDATE/HISTORY_DATABASE_UPDATE
  # already had as SPARQL::Client instances under GraphDB, so call sites in
  # lib/queries.rb didn't need to change.
  class VirtuosoUpdateClient
    def initialize(endpoint:, user:, password:)
      @uri = URI(endpoint)
      @uri.user = user
      @uri.password = password
      @digest_auth = Net::HTTP::DigestAuth.new
    end

    def update(query)
      http = Net::HTTP.new(@uri.host, @uri.port)

      challenge = post(http, query)
      raise "Virtuoso did not challenge for auth as expected (got #{challenge.code})" unless challenge.code == '401'

      auth_header = @digest_auth.auth_header(@uri, challenge['www-authenticate'], 'POST')
      response = post(http, query, auth_header)

      unless response.is_a?(Net::HTTPSuccess)
        raise "Virtuoso SPARQL Update failed: #{response.code} #{response.message}\n#{response.body}"
      end

      response
    end

    # Matches SPARQL::Client#insert_data's shape (used by
    # delete_dataset_query to snapshot a CONSTRUCT result into the history
    # store) - reuses SPARQL::Client::Update::InsertData purely to serialize
    # +data+ into "INSERT DATA { GRAPH <...> {...} }" text, identical to what
    # ran under GraphDB, then sends it through the same digest-authenticated
    # #update above rather than SPARQL::Client's own (Basic-auth-only) HTTP
    # layer.
    #
    # @param data [RDF::Enumerable] triples to insert
    # @param graph [RDF::URI, String] target named graph
    def insert_data(data, graph:)
      update(SPARQL::Client::Update::InsertData.new(data, graph: graph).to_s)
    end

    private

    def post(http, query, auth_header = nil)
      req = Net::HTTP::Post.new(@uri)
      req['Authorization'] = auth_header if auth_header
      req.set_form_data('update' => query)
      http.request(req)
    end
  end
end
