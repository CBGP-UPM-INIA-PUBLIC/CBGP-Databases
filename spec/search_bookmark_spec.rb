# frozen_string_literal: true

require 'rack/test'
require_relative '../app/controllers/application_controller'

# A search typed into the form is a POST, which has no address worth keeping. It is
# answered with a redirect to the same search as a plain link holding only the boxes
# that were filled in, so the results page can be bookmarked, shared and re-run later
# (a "today" in it is read on the day the link is opened).
RSpec.describe 'a posted search lands on a bookmarkable address', type: :request do
  include Rack::Test::Methods

  def app
    CBGP::DatabasesApp
  end

  before do
    header 'Host', 'localhost'
    post '/cbgp/login', username: 'test-admin', password: 'test'
  end

  def location_query
    Rack::Utils.parse_nested_query(URI(last_response.headers['Location']).query.to_s)
  end

  describe 'compact_search_params' do
    it 'drops blank boxes and keeps what was filled in' do
      kept = compact_search_params('t' => '', 's' => 'Awarded', 'd' => { 'start' => '', 'end' => 'today' },
                                   'e' => { 'start' => '', 'end' => ' ' }, 'l' => ['', 'a'], 'n' => ['', ' '])
      expect(kept).to eq('s' => 'Awarded', 'd' => { 'end' => 'today' }, 'l' => ['a'])
    end

    it 'is nil when nothing was filled in' do
      expect(compact_search_params('t' => '', 'd' => { 'start' => '' })).to be_nil
    end
  end

  it 'redirects the form\'s post to a GET with only the filled-in boxes, today included' do
    post '/cbgp/query-dataset/project', 'project_title' => '', 'project_status' => 'awarded',
                                         'project_start_date' => { 'start' => '', 'end' => 'today' },
                                         'project_end_date' => { 'start' => 'today', 'end' => '' },
                                         'project_end_date__orempty' => '1'

    expect(last_response.status).to be_between(301, 303)
    expect(last_response.headers['Location']).to include('/cbgp/query-dataset/project?')
    expect(location_query).to eq('project_status' => 'awarded',
                                 'project_start_date' => { 'end' => 'today' },
                                 'project_end_date' => { 'start' => 'today' },
                                 'project_end_date__orempty' => '1')
  end

  it 'sends an entirely blank form to the plain address, which says nothing was entered' do
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:execute_search).and_return([])
    post '/cbgp/query-dataset/project', 'project_title' => '', 'project_start_date' => { 'start' => '', 'end' => '' }

    expect(last_response.headers['Location']).to end_with('/cbgp/query-dataset/project')
    get URI(last_response.headers['Location']).request_uri
    expect(last_response.status).to eq(200)
  end

  it 'gives the same results from the posted form and from the link it redirects to' do
    seen = []
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:execute_search) do |*args, **kw|
      seen << (kw.empty? ? args.last : kw)[:search_params].to_h
      []
    end
    post '/cbgp/query-dataset/project', 'project_status' => 'awarded', 'project_title' => ''
    get URI(last_response.headers['Location']).request_uri

    expect(seen.size).to eq(1)
    expect(seen.first).to include('project_status' => 'awarded')
    expect(seen.first.keys).not_to include('project_title')
  end

  it 'encodes a path-hostile database name' do
    post '/cbgp/query-dataset/a%20b', 'x' => '1'
    expect(last_response.headers['Location']).to include('/cbgp/query-dataset/a%20b?')
  end
end
