# frozen_string_literal: true

# McpTools::Shared::FunderLookup (lib/mcp_tools/shared/funder_lookup.rb) -
# thin passthrough to ROR's affiliation-matching API, no database access.
# RestClient::Request.execute is stubbed throughout with a real ROR
# response shape (verified live against api.ror.org while building this),
# never a live network call in specs.
RSpec.describe McpTools::Shared::FunderLookup do
  def ror_response(items)
    instance_double(RestClient::Response, body: { number_of_results: items.size, items: items }.to_json)
  end

  def ror_item(score:, chosen:, name:, types:, acronym: nil, country: 'United Kingdom', ror_id: 'https://ror.org/029chgv08')
    names = [{ 'lang' => 'en', 'types' => %w[ror_display label], 'value' => name }]
    names << { 'lang' => nil, 'types' => ['acronym'], 'value' => acronym } if acronym

    {
      'score' => score,
      'chosen' => chosen,
      'organization' => {
        'id' => ror_id,
        'types' => types,
        'names' => names,
        'locations' => [{ 'geonames_details' => { 'country_name' => country } }]
      }
    }
  end

  it 'extracts name, acronym, types, country, score, and ror_chosen from each candidate' do
    allow(RestClient::Request).to receive(:execute)
      .with(hash_including(url: a_string_matching(%r{ror\.org.*Wellcome})))
      .and_return(ror_response([ror_item(score: 1.0, chosen: true, name: 'Wellcome Trust', types: %w[funder nonprofit], acronym: 'WT')]))

    body = JSON.parse(described_class.call({ 'name' => 'Wellcome Trust' }).first[:text])

    expect(body['query']).to eq('Wellcome Trust')
    candidate = body['candidates'].first
    expect(candidate).to include(
      'ror_id' => 'https://ror.org/029chgv08', 'name' => 'Wellcome Trust', 'acronym' => 'WT',
      'types' => %w[funder nonprofit], 'country' => 'United Kingdom', 'score' => 1.0, 'ror_chosen' => true
    )
  end

  it 'returns an empty candidate list, not an error, when nothing matches (a normal outcome for an obscure/new funder)' do
    allow(RestClient::Request).to receive(:execute).and_return(ror_response([]))

    body = JSON.parse(described_class.call({ 'name' => 'World Duchenne Organization' }).first[:text])

    expect(body['candidates']).to eq([])
  end

  it 'returns multiple ranked candidates in ROR\'s own order, including low-score non-matches, without picking one itself' do
    items = [
      ror_item(score: 0.9, chosen: false, name: 'Hope Organization', types: ['other'], ror_id: 'https://ror.org/aaa'),
      ror_item(score: 0.6, chosen: false, name: 'World Down Syndrome Foundation', types: ['nonprofit'], ror_id: 'https://ror.org/bbb')
    ]
    allow(RestClient::Request).to receive(:execute).and_return(ror_response(items))

    body = JSON.parse(described_class.call({ 'name' => 'World Duchenne Organization' }).first[:text])

    expect(body['candidates'].size).to eq(2)
    expect(body['candidates'].map { |c| c['ror_chosen'] }).to eq([false, false])
  end

  it 'raises a clear error rather than propagating a raw network exception' do
    allow(RestClient::Request).to receive(:execute).and_raise(RestClient::Exceptions::Timeout.new)

    expect { described_class.call({ 'name' => 'Anything' }) }.to raise_error(/ROR lookup failed/)
  end

  it 'raises on a blank name rather than querying ROR with nothing' do
    expect(RestClient::Request).not_to receive(:execute)
    expect { described_class.call({ 'name' => '  ' }) }.to raise_error(ArgumentError)
  end
end
