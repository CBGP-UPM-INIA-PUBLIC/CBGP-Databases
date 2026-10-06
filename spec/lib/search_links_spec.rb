# frozen_string_literal: true

require 'rack/test'
require 'cgi'
require_relative '../../app/controllers/application_controller'

# "Every value is a link": each value shown on a result page is a plain link to
# an exact-match search for itself (search_link_html in lib/core.rb), answered
# by GET /cbgp/query-dataset/:database with a "<questionclass>__exact" flag
# (build_search_query in lib/queries.rb). Typed searches stay "contains,
# ignoring case and accents"; only the links are exact. The TSV download must
# never see any of this.
RSpec.describe 'exact-match search (the link searches)' do
  def query(params = {}, type: 'member', **string_keyed)
    build_search_query(search_params: params.merge(string_keyed), dataset_type: type)
  end

  it 'compares the stored text verbatim instead of a regex' do
    q = query('member_name' => 'María', 'member_name__exact' => '1')
    expect(q).to include('FILTER(STR(?value_0) = "María")')
    expect(q).not_to include('regex')
  end

  it 'leaves a typed search (no flag) as the forgiving regex' do
    q = query('member_name' => 'María')
    expect(q).to include('FILTER regex(STR(?value_0)')
    expect(q).not_to include('STR(?value_0) = ')
  end

  it 'does not treat the flag as a field of its own' do
    q = query('member_name' => 'Ana', 'member_name__exact' => '1')
    expect(q.scan(/rdf:type cbgp:\w+/)).to eq(['rdf:type cbgp:member_name'])
  end

  it 'makes only the flagged field exact' do
    q = query('member_name' => 'Ana', 'member_name__exact' => '1', 'member_surnames' => 'gar')
    expect(q).to include('= "Ana")', 'FILTER regex(STR(?value_1), "g[a')
  end

  it 'does not re-parse a stored currency amount as typed input' do
    q = query({ 'personnel_project_total_funding' => '15000.50', 'personnel_project_total_funding__exact' => '1' },
              type: 'personnel_project')
    expect(q).to include('FILTER(STR(?value_0) = "15000.50")')
    expect(q).not_to include('CONTAINS')
  end

  it 'composes with NOT' do
    q = query('member_name' => 'Ana', 'member_name__exact' => '1', 'member_name__not' => '1')
    expect(q).to match(/FILTER NOT EXISTS \{[^}]*FILTER\(STR\(\?value_0\) = "Ana"\)/m)
  end

  it 'does nothing for a flag whose field has no value' do
    expect(query('member_name__exact' => '1')).to be_nil
  end

  ['a"b', 'a\\b', 'x") } ; DROP ALL #', "O'Brien", "multi\nline", 'Muñoz, José (2) [x]'].each do |value|
    it "keeps #{value.inspect} inside the string literal" do
      q = query('member_name' => value, 'member_name__exact' => '1')
      expect { SPARQL.parse(q) }.not_to raise_error
      expect(q.scan(/FILTER\(STR/).size).to eq(1)
    end
  end
end

RSpec.describe 'search_link_html' do
  let(:text_field) { { questionclass: 'member_name', widget: 'text', class: 'string' } }

  def href_of(html)
    CGI.unescapeHTML(html[/href="([^"]*)"/, 1])
  end

  it 'links a value to an exact-match search of the database being shown' do
    html = search_link_html(field: text_field, database: 'member', value: 'Ana')
    expect(href_of(html)).to eq('/cbgp/query-dataset/member?member_name=Ana&member_name__exact=1')
    expect(html).to include('class="search-link"', '>Ana</a>')
  end

  it 'shows the label but links on the stored value' do
    html = search_link_html(field: text_field, database: 'member', value: 'ID-7', text: 'Spain', title: 'Spain')
    expect(href_of(html)).to include('member_name=ID-7')
    expect(html).to include('>Spain</a>', 'title="Spain"')
  end

  it 'round-trips awkward characters through the URL and escapes them in the markup' do
    value = %(a&b=c,d;e "q" <i>é ñ / ?)
    html = search_link_html(field: text_field, database: 'member', value: value)
    expect(Rack::Utils.parse_query(URI(href_of(html)).query)['member_name']).to eq(value)
    expect(html).not_to include('<i>', '"q"')
    expect(html.scan('href=').size).to eq(1)
  end

  it 'escapes the database name in the path' do
    html = search_link_html(field: text_field, database: 'a/b c', value: 'x')
    expect(href_of(html)).to start_with('/cbgp/query-dataset/a%2Fb%20c?')
  end

  it 'is plain escaped text for a blank value' do
    expect(search_link_html(field: text_field, database: 'member', value: '  ')).not_to include('<a')
    expect(search_link_html(field: text_field, database: 'member', value: nil, text: '-')).to eq('-')
  end

  it 'is plain escaped text for prose (textfield widgets)' do
    html = search_link_html(field: text_field.merge(widget: 'textfield'), database: 'member', value: 'a <b> note')
    expect(html).to eq('a &lt;b&gt; note')
  end

  describe 'numbers, amounts and dates stay plain text' do
    {
      'a number widget' => { widget: 'number', class: 'number' },
      'a currency widget' => { widget: 'currency', class: 'currency' },
      'a date widget' => { widget: 'date', class: 'date' },
      'a date widget with a string class (how most project dates are declared)' => { widget: 'date', class: 'string' },
      'an integer in a text box (a year)' => { widget: 'text', class: 'integer' }
    }.each do |name, attrs|
      it "for #{name}" do
        html = search_link_html(field: text_field.merge(attrs), database: 'member', value: '2026')
        expect(html).to eq('2026')
      end
    end

    it 'while a plain string in a text box is still a link' do
      expect(search_link_html(field: text_field, database: 'member', value: '2026')).to include('<a ')
    end

    it 'for every number, currency and date field of the live ontology' do
      %w[funding_commitment european_research_project member personnel_project publication].each do |form|
        CBGP::Dataset.fields_for(form).each do |f|
          next unless %w[number currency date].include?(f[:widget].to_s.split('#').last) || %w[number currency date].include?(f[:class])

          expect(search_linkable_field?(f)).to be(false), "#{form}.#{f[:questionclass]} should not be a link"
        end
      end
    end
  end

  it 'is plain text for a multi-line value even when the widget is a one-line text box' do
    html = search_link_html(field: text_field, database: 'member', value: "Actual: x\r\nAnterior: y")
    expect(html).not_to include('<a')
    expect(html).to include('Actual: x')
  end

  it 'leaves url fields to url_link_html' do
    expect(search_link_html(field: text_field.merge(class: 'url'), database: 'member', value: 'https://x.org'))
      .not_to include('<a')
  end

  describe 'cross-reference fields' do
    let(:xref) do
      { questionclass: 'commitment_member', widget: 'text', class: 'string', references_target: 'member',
        references_via: 'https://w3id.org/CBGP-App#member_dni_nie_pas' }
    end

    it "search the referenced form's key field for the stored key" do
      allow(CBGP::Dataset).to receive(:fields_for).with('member').and_return([{ questionclass: 'member_dni_nie_pas' }])
      html = search_link_html(field: xref, database: 'funding_commitment', value: '00831666D', text: 'Álvarez')
      expect(href_of(html)).to eq('/cbgp/query-dataset/member?member_dni_nie_pas=00831666D&member_dni_nie_pas__exact=1')
      expect(html).to include('>Álvarez</a>')
    end

    it 'falls back to the field itself when the target form has no such key field' do
      allow(CBGP::Dataset).to receive(:fields_for).with('member').and_return([])
      html = search_link_html(field: xref, database: 'funding_commitment', value: 'K')
      expect(href_of(html)).to start_with('/cbgp/query-dataset/funding_commitment?commitment_member=K')
    end

    it 'falls back the same way when the target cannot be looked up at all' do
      allow(CBGP::Dataset).to receive(:fields_for).and_raise('boom')
      html = search_link_html(field: xref, database: 'funding_commitment', value: 'K')
      expect(href_of(html)).to start_with('/cbgp/query-dataset/funding_commitment?commitment_member=K')
    end
  end

  it 'only ever targets real, existing member fields in the live ontology' do
    CBGP::Dataset.fields_for('funding_commitment').select { |f| f[:references_target] }.each do |field|
      db, qc = search_link_target(field, 'funding_commitment')
      expect(CBGP::Dataset.fields_for(db).map { |f| f[:questionclass] }).to include(qc)
    end
  end
end

RSpec.describe 'the search results page', type: :request do
  include Rack::Test::Methods

  def app
    CBGP::DatabasesApp
  end

  let(:record) do
    ds = CBGP::Dataset.new(type: 'member')
    ds.primary_id = 'm-1'
    name_field = CBGP::Dataset.fields_for('member').find { |f| f[:questionclass] == 'member_name' }
    ds.public_send("#{name_field[:method]}=", 'Ana <b>&</b> María')
    ds
  end

  before do
    header 'Host', 'localhost'
    post '/cbgp/login', username: 'test-admin', password: 'test'
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:execute_search).and_return(['graph://m-1'])
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:batch_retrieve_dataset_ids).and_return('graph://m-1' => 'm-1')
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:fetch_datasets_raw_data).and_return([])
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:batch_retrieve_record_forms).and_return({})
    allow(CBGP::Dataset).to receive(:load_from_graph).and_return(record)
    allow(CBGP::RelatedRecords).to receive(:result_warnings).and_return(messages: [], skipped: 0)
  end

  def html_without_tsv_link
    last_response.body.gsub(/<a href="data:[^"]*"/, '')
  end

  it 'answers a GET with the same results as the form POST' do
    get '/cbgp/query-dataset/member', 'member_name' => 'Ana', 'member_name__exact' => '1'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Search Results')
  end

  it 'passes the exact flag through to the search' do
    expect_any_instance_of(CBGP::DatabasesApp).to receive(:execute_search) do |_app, **kw|
      expect(kw[:search_params]).to include('member_name' => 'Ana', 'member_name__exact' => '1')
      []
    end
    get '/cbgp/query-dataset/member', 'member_name' => 'Ana', 'member_name__exact' => '1'
  end

  it 'renders each value as an escaped exact-match link' do
    get '/cbgp/query-dataset/member', 'member_name' => 'x'
    expect(last_response.body).to include('class="search-link"')
    expect(last_response.body).to include('/cbgp/query-dataset/member?member_name=Ana+%3Cb%3E%26%3C%2Fb%3E+Mar%C3%ADa&amp;member_name__exact=1')
    expect(last_response.body).not_to include('<b>&</b>')
  end

  it 'does not leak a single link into the TSV download' do
    get '/cbgp/query-dataset/member', 'member_name' => 'x'
    uri = last_response.body[/href="(data:text\/tab-separated-values;base64,[^"]+)"/, 1]
    expect(uri).not_to be_nil
    tsv = Base64.decode64(uri.split(',', 2).last).force_encoding('UTF-8')
    expect(tsv).to include('Ana <b>&</b> María')
    expect(tsv).not_to match(/<a |href|search-link|__exact/)
  end

  it 'keeps the VIEW/EDIT and DELETE links' do
    get '/cbgp/query-dataset/member', 'member_name' => 'x'
    expect(html_without_tsv_link).to include('/cbgp/dataset/member/m-1')
    expect(html_without_tsv_link).to match(%r{<a href="/cbgp/dataset/member/m-1"[^>]*>\s*VIEW/EDIT\s*</a>})
  end
end
