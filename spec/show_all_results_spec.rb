# frozen_string_literal: true

require 'rack/test'
require_relative '../app/controllers/application_controller'

# What the results page says about the search itself: "Show all records"
# (__all=1) says it is showing everything, and a form submitted with every box
# empty says nothing was entered (rather than "no results found") and offers
# the Show all link. A search on a dbname several forms share shows only the
# fields they have in common as columns.
RSpec.describe 'search results: show all and empty searches', type: :request do
  include Rack::Test::Methods

  def app
    CBGP::DatabasesApp
  end

  let(:graphs) { %w[graph://a graph://b] }
  let(:records) do
    graphs.each_with_index.to_h do |g, i|
      ds = CBGP::Dataset.new(type: 'project')
      ds.primary_id = "p-#{i}"
      [g, ds]
    end
  end
  let(:seen_params) { [] }

  before do
    header 'Host', 'localhost'
    post '/cbgp/login', username: 'test-admin', password: 'test'
    found = found_graphs
    captured = seen_params
    # |*args, **kw| (not |_app, search_params:|): rspec-mocks mishandles keyword args in stub blocks here
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:execute_search) do |*args, **kw|
      search_params = (kw.empty? ? args.last : kw)[:search_params]
      captured << search_params
      search_params['__all'] == '1' ? found : []
    end
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:batch_retrieve_dataset_ids)
      .and_return(records.transform_values(&:primary_id))
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:fetch_datasets_raw_data).and_return([])
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:batch_retrieve_record_forms).and_return({})
    allow(CBGP::Dataset).to receive(:load_from_graph) { |*args, **kw| records.fetch((kw.empty? ? args.last : kw)[:graph]) }
    allow(CBGP::RelatedRecords).to receive(:result_warnings).and_return(messages: [], skipped: 0)
  end

  let(:found_graphs) { graphs }

  it 'passes the show-all request on to the search, and says everything is shown' do
    get '/cbgp/query-dataset/project?__all=1'

    expect(seen_params.last['__all']).to eq('1')
    expect(last_response.body).to include('Showing all records (2).')
    expect(last_response.body).not_to include('Nothing was entered to search for.')
  end

  it 'says nothing was entered, and offers Show all, for a form submitted with every box empty' do
    post '/cbgp/query-dataset/project', 'project_title' => '', 'project_status' => '', 'project_start_date' => { 'start' => '', 'end' => '' }

    expect(last_response.body).to include('Nothing was entered to search for.')
    expect(last_response.body).to include('href="/cbgp/query-dataset/project?__all=1"')
    expect(last_response.body).not_to include('No results found for your search.')
  end

  it 'still says "no results" for a real search that found nothing' do
    post '/cbgp/query-dataset/project', 'project_title' => 'zzz'

    expect(last_response.body).to include('No results found for your search.')
    expect(last_response.body).not_to include('Nothing was entered to search for.')
  end

  it 'does not show the all-records notice for an ordinary search' do
    post '/cbgp/query-dataset/project', 'project_title' => 'zzz'

    expect(last_response.body).not_to include('Showing all records')
  end

  it 'shows a shared dbname\'s results with only the fields its forms have in common as columns' do
    get '/cbgp/query-dataset/project?__all=1'

    headers = last_response.body[%r{<thead>.*?</thead>}m].scan(%r{<th>(.*?)</th>}m).flatten.map(&:strip)
    common = CBGP::Dataset.common_fields_for('project').map { |f| f[:label] }
    only_some = CBGP::Dataset.fields_for('project').map { |f| f[:label] } - common

    expect(headers).to include(*common)
    expect(only_some).not_to be_empty
    expect(headers & only_some).to be_empty
  end

  it 'repeats a show-all search when it is replayed from the session (e.g. after a delete)' do
    get '/cbgp/query-dataset/project?__all=1'
    get '/cbgp/last-search/project'

    expect(last_response.body).to include('Showing all records (2).')
  end
end
