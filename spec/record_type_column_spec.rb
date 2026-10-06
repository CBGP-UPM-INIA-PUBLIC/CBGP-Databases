# frozen_string_literal: true

require 'rack/test'
require 'base64'
require_relative '../app/controllers/application_controller'

# Every search result row says what kind of record it is (the form that wrote
# it - "Personnel Project" vs "National and Regional Research Projects"),
# read from the dcterms:type stamp each record carries, in one batched query.
RSpec.describe 'the Record type column on search results', type: :request do
  include Rack::Test::Methods

  def app
    CBGP::DatabasesApp
  end

  # loaded the way a search of the shared "project" dbname loads them: typed by
  # the dbname (every project form's fields); which form WROTE each record is
  # what the stamp (the +forms+ map below) says
  def record(_form, id)
    ds = CBGP::Dataset.new(type: 'project')
    ds.primary_id = id
    ds
  end

  let(:records) do
    { 'graph://p1' => record('personnel_project', 'p-1'),
      'graph://n1' => record('national_regional_research_project', 'n-1'),
      'graph://old' => record('personnel_project', 'old-1') }
  end
  let(:forms) do
    { 'graph://p1' => 'personnel_project', 'graph://n1' => 'national_regional_research_project' } # 'old' has no stamp
  end

  before do
    header 'Host', 'localhost'
    post '/cbgp/login', username: 'test-admin', password: 'test'
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:execute_search).and_return(records.keys)
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:batch_retrieve_dataset_ids)
      .and_return(records.transform_values(&:primary_id))
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:fetch_datasets_raw_data).and_return([])
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:batch_retrieve_record_forms).and_return(forms)
    # |*args, **kw| (not |graph:, **|): rspec-mocks mishandles keyword args in stub blocks here
    allow(CBGP::Dataset).to receive(:load_from_graph) { |*args, **kw| records.fetch((kw.empty? ? args.last : kw)[:graph]) }
    allow(CBGP::RelatedRecords).to receive(:result_warnings).and_return(messages: [], skipped: 0)
  end

  def table_rows
    last_response.body.scan(%r{<tr>\s*<td>.*?</tr>}m)
  end

  def tsv
    uri = last_response.body[%r{href="(data:text/tab-separated-values;base64,[^"]+)"}, 1]
    Base64.decode64(uri.split(',', 2).last).force_encoding('UTF-8')
  end

  it 'adds a Record type column header right after Action' do
    get '/cbgp/query-dataset/project'
    expect(last_response.body).to match(%r{<th>Action</th>\s*<th>Record type</th>})
  end

  it 'names each row\'s own kind of record, so a mixed result is told apart per row' do
    get '/cbgp/query-dataset/project'
    expect(table_rows.size).to eq(3)
    expect(table_rows[0]).to include('>' + record_type_label('personnel_project') + '</a>')
    expect(table_rows[1]).to include('>' + record_type_label('national_regional_research_project') + '</a>')
    expect(record_type_label('personnel_project')).not_to eq(record_type_label('national_regional_research_project'))
  end

  it 'links the type to a search listing every record of that form' do
    get '/cbgp/query-dataset/project'
    expect(table_rows[0]).to include('href="/cbgp/query-dataset/personnel_project"')
    expect(table_rows[1]).to include('href="/cbgp/query-dataset/national_regional_research_project"')
  end

  it 'shows a dash, not a link, for a record that carries no stamp' do
    get '/cbgp/query-dataset/project'
    expect(table_rows[2]).not_to include('query-dataset/personnel_project"')
    expect(table_rows[2]).to match(%r{<td>-</td>})
  end

  it 'is there for a POST search too, and for any kind of record' do
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:batch_retrieve_record_forms)
      .and_return('graph://p1' => 'member')
    post '/cbgp/query-dataset/project', 'project_title' => 'x'
    expect(table_rows[0]).to include('href="/cbgp/query-dataset/member"', '>' + record_type_label('member') + '</a>')
  end

  it 'is there when the last search is replayed' do
    post '/cbgp/query-dataset/project', 'project_title' => 'x'
    get '/cbgp/last-search/project'
    expect(last_response.body).to include('<th>Record type</th>', 'href="/cbgp/query-dataset/personnel_project"')
  end

  it 'puts the type into the TSV download as plain text, no markup' do
    get '/cbgp/query-dataset/project'
    lines = tsv.lines.map { |l| l.chomp.split("\t").map { |c| c.delete('"') } }
    expect(lines[0][0, 2]).to eq(['Dataset ID', 'Record type'])
    expect(lines[1][0, 2]).to eq(['p-1', record_type_label('personnel_project')])
    expect(lines[3][0, 2]).to eq(['old-1', '-'])
    expect(tsv).not_to match(/<a |href|search-link/)
  end

  it 'asks the store once for the whole page, not once per row' do
    expect_any_instance_of(CBGP::DatabasesApp).to receive(:batch_retrieve_record_forms).once.and_return(forms)
    get '/cbgp/query-dataset/project'
  end

  it 'still lists the results when the types cannot be read' do
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:batch_retrieve_record_forms).and_return({})
    get '/cbgp/query-dataset/project'
    expect(last_response.status).to eq(200)
    expect(table_rows.size).to eq(3)
  end
end

RSpec.describe 'record type helpers' do
  it 'labels a form with its ontology name, falling back to the id, and a dash for none' do
    expect(record_type_label('personnel_project')).to be_a(String).and satisfy { |s| !s.empty? && s != '-' }
    expect(record_type_label(nil)).to eq('-')
    expect(record_type_label('  ')).to eq('-')
  end

  it 'escapes everything in the link' do
    allow(self).to receive(:cached_label_for_id).and_return('<b>"x"</b>')
    html = record_type_link_html('a b&c')
    expect(html).to include('href="/cbgp/query-dataset/a%20b%26c"')
    expect(html).not_to include('<b>')
  end
end

RSpec.describe 'batch_retrieve_record_forms' do
  it 'maps each graph to the local name of its stamped form in one query' do
    seen = []
    allow(DATABASE).to receive(:query) do |q|
      seen << q
      [{ graph: RDF::URI('https://x.org/g/1'), form: RDF::URI('https://w3id.org/CBGP-App#personnel_project') },
       { graph: RDF::URI('https://x.org/g/2'), form: RDF::URI('https://w3id.org/CBGP-App#member') }]
    end

    result = batch_retrieve_record_forms(graph_uris: ['https://x.org/g/1', 'https://x.org/g/2', 'https://x.org/g/3'])

    expect(result).to eq('https://x.org/g/1' => 'personnel_project', 'https://x.org/g/2' => 'member')
    expect(seen.size).to eq(1)
    expect(seen.first).to include('<https://x.org/g/1>', '<https://x.org/g/3>', 'dcterms:type ?form')
  end

  it 'asks nothing for no graphs' do
    expect(DATABASE).not_to receive(:query)
    expect(batch_retrieve_record_forms(graph_uris: [])).to eq({})
  end

  it 'returns {} rather than raising when the store is down' do
    allow(DATABASE).to receive(:query).and_raise('down')
    expect(batch_retrieve_record_forms(graph_uris: ['https://x.org/g/1'])).to eq({})
  end
end
