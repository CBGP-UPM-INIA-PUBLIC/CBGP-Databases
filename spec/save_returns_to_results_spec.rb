# frozen_string_literal: true

require 'rack/test'
require_relative '../app/controllers/application_controller'

# Saving an edit to an existing record that was reached from a search goes
# back to those search results (with a notice, and any advisory warning) so
# the next neighbouring record can be opened; everything else keeps showing
# the saved record. See POST /cbgp/validate-dataset/:database and
# GET /cbgp/last-search/:database in app/controllers/routes.rb.
RSpec.describe 'saving returns to the search results', type: :request do
  include Rack::Test::Methods

  def app
    CBGP::DatabasesApp
  end

  let(:entry) do
    ds = CBGP::Dataset.new(type: 'funding_commitment')
    ds.primary_id = 'c-1'
    ds
  end

  let(:warning_panel) do
    CBGP::RelatedRecords::Panel.new(
      title: "This member's funding commitments", related_form: 'funding_commitment', related_form_label: 'Funding Commitment',
      columns: [], rows: [], total: BigDecimal('91'), sum_label: 'Percentage of salary cost',
      expected_total: BigDecimal('100'), tolerance: BigDecimal('0.05'), active_count: 2, warning: true,
      issues: [{ date: Date.today, total: BigDecimal('91') }], as_of: Date.today, subject: 'García (12345678Z)',
      add_path: '/cbgp/dataset/funding_commitment'
    )
  end

  let(:save_params) { { 'form_class' => 'funding_commitment', 'primary_id' => 'c-1' } }

  before do
    header 'Host', 'localhost'
    post '/cbgp/login', username: 'test-admin', password: 'test'
    allow(CBGP::Dataset).to receive(:load_from_params_and_write).and_return(entry)
    allow(CBGP::Triggers).to receive(:check_and_fire)
    allow(CBGP::RelatedRecords).to receive(:panels_for).and_return([])
    # a search, so the session has something to return to
    allow(CBGP::RelatedRecords).to receive(:execute_search).and_return([])
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:execute_search).and_return(['graph://c-1'])
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:batch_retrieve_dataset_ids).and_return('graph://c-1' => 'c-1')
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:fetch_datasets_raw_data).and_return([])
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:batch_retrieve_record_forms).and_return({})
    allow(CBGP::Dataset).to receive(:load_from_graph).and_return(entry)
  end

  # Rack::Test's follow_redirect! re-targets the absolute Location's host and
  # drops the session cookie that was issued for the stubbed 'localhost' Host.
  def follow_redirect_with_session
    get URI(last_response.headers['Location']).path
  end

  def search!
    get '/cbgp/query-dataset/funding_commitment', 'commitment_project' => 'X'
  end

  it 'redirects an edit made from a search back to the results, with a notice' do
    search!
    post '/cbgp/validate-dataset/commitment', save_params

    expect([302, 303]).to include(last_response.status) # 303 from the real server, 302 under Rack::Test
    expect(last_response.headers['Location']).to end_with('/cbgp/last-search/funding_commitment')

    follow_redirect_with_session
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Search Results', 'Record saved.')
  end

  it 'carries an advisory panel warning along as a flash' do
    search!
    allow(CBGP::RelatedRecords).to receive(:panels_for).and_return([warning_panel])
    post '/cbgp/validate-dataset/commitment', save_params
    follow_redirect_with_session

    expect(last_response.body).to include('flash-warning')
    expect(last_response.body).to include('adds up to 91.00', 'expected 100.00')
  end

  it 'shows no warning flash when the panels have none' do
    search!
    post '/cbgp/validate-dataset/commitment', save_params
    follow_redirect_with_session

    expect(last_response.body).not_to include('class="flash-warning"')
  end

  # Anything else goes to the saved record's own, bookmarkable address (never
  # left on the POST URL, which has no record to give back when reloaded).
  it 'sends a brand-new record (no primary_id yet) to its own address' do
    search!
    post '/cbgp/validate-dataset/commitment', save_params.merge('primary_id' => '')

    expect(last_response.status).to eq(302)
    expect(last_response.headers['Location']).to end_with('/cbgp/dataset/funding_commitment/c-1')
  end

  it 'sends the saved record to its own address when the session has no search for that form' do
    post '/cbgp/validate-dataset/commitment', save_params

    expect(last_response.status).to eq(302)
    expect(last_response.headers['Location']).to end_with('/cbgp/dataset/funding_commitment/c-1')
  end

  it 'sends the saved record to its own address when the last search was on a different form' do
    get '/cbgp/query-dataset/member', 'member_surnames' => 'X'
    post '/cbgp/validate-dataset/commitment', save_params

    expect(last_response.status).to eq(302)
    expect(last_response.headers['Location']).to end_with('/cbgp/dataset/funding_commitment/c-1')
  end

  it 'escapes a path-hostile form or id in that address' do
    entry.primary_id = 'a b/c'
    post '/cbgp/validate-dataset/commitment', save_params.merge('primary_id' => '')

    expect(last_response.headers['Location']).to end_with('/cbgp/dataset/funding_commitment/a%20b%2Fc')
  end

  describe 'GET /cbgp/last-search/:database' do
    it 'falls back to the search form when this session has no such search' do
      get '/cbgp/last-search/funding_commitment'

      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to end_with('/cbgp/search-dataset/funding_commitment')
    end

    it 'escapes the flash text rather than injecting it' do
      search!
      allow(CBGP::RelatedRecords).to receive(:panels_for).and_return([warning_panel.tap { |p| p.title = '<b>x</b>' }])
      post '/cbgp/validate-dataset/commitment', save_params
      follow_redirect_with_session

      expect(last_response.body).not_to include('<b>x</b>')
    end
  end
end
