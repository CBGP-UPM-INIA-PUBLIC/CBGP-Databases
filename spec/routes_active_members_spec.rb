# frozen_string_literal: true

require 'rack/test'
require_relative '../app/controllers/application_controller'

# Regression coverage for a real bug found 2026-08-26: /cbgp/active-members
# and /cbgp/active-emails (an external XML feed Gonzalo's pipeline consumes)
# searched on a hardcoded, obscure ontology fragment ('mem17') for the member
# status field, instead of the real questionclass (member_status). This
# predates Sara's ontology restructuring and was never updated - since a
# nonexistent questionclass makes build_search_query silently skip that
# condition entirely (warns and returns nil), both feeds had been returning
# zero members - not erroring, just silently empty - for some unknown
# length of time before this was noticed.
#
# 'mem17' is exactly the kind of obscure auto-generated ontology fragment
# name (see also the already-fixed 'newpub4' in lib/loaders.rb) the user
# asked to be swept for and replaced with meaningful questionclass names
# wherever found.
RSpec.describe 'active-members / active-emails feeds', type: :request do
  include Rack::Test::Methods

  def app
    CBGP::DatabasesApp
  end

  before do
    header 'Host', 'localhost'
    # execute_search/batch_retrieve_dataset_ids/fetch_datasets_raw_data are
    # bare top-level functions (see lib/queries.rb), not CBGP::Dataset
    # methods - within a Sinatra route their implicit receiver is the app
    # instance, so that's what has to be stubbed to intercept the call.
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:batch_retrieve_dataset_ids).and_return({})
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:fetch_datasets_raw_data).and_return([])
  end

  it 'searches on the real member_status questionclass, not the stale "mem17" fragment' do
    expect_any_instance_of(CBGP::DatabasesApp).to receive(:execute_search)
      .with(hash_including(search_params: { 'member_status' => 'active' }, dataset_type: 'member'))
      .and_return([])

    get '/cbgp/active-members'

    expect(last_response.status).to eq(200)
  end

  it 'active-emails also searches on member_status, not "mem17"' do
    expect_any_instance_of(CBGP::DatabasesApp).to receive(:execute_search)
      .with(hash_including(search_params: { 'member_status' => 'active' }, dataset_type: 'member'))
      .and_return([])

    get '/cbgp/active-emails'

    expect(last_response.status).to eq(200)
  end

  # Real, populated data - the empty-result specs above wouldn't have caught
  # a second real bug found alongside the mem17 one: xmlmembers.erb called
  # d.member_code10/d.member_cbgp_center_board/d.member_gender/d.member_cluster
  # (questionclass strings, not real Dataset method names - should have been
  # d.code_10/d.consejo/d.gender/d.cluster) and chained a bare `.strip` onto
  # get_label_for_id's result, which raises NoMethodError on nil whenever
  # that field is blank. Both routes had silently returned zero results ever
  # since Sara's ontology restructuring (the mem17 bug), so this template had
  # apparently never actually rendered a real member before either bug was
  # found - this is what a real request would have hit next.
  describe 'rendering a real populated member record' do
    let(:member) do
      ds = CBGP::Dataset.new(type: 'member')
      ds.primary_id = 'abc-123'
      ds.name = 'Ada'
      ds.surname = 'Lovelace'
      ds.institutional_mail = 'ada@example.org'
      ds.lab = 'B1'
      ds.lab_phone_number = ''
      ds.office = ''
      ds.category = 'phd_candidate'
      ds.pi = 'team_leader_no'
      ds.research_area = ''
      ds.institution = 'CSIC-INIA'
      ds.code_10 = ''
      ds.consejo = ''
      ds.gender = ''
      ds.cluster = '' # blank on purpose - this is exactly what used to crash
      ds
    end

    before do
      allow_any_instance_of(CBGP::DatabasesApp).to receive(:execute_search).and_return(['graph://member/1'])
      allow(CBGP::Dataset).to receive(:load_from_graph)
        .with(hash_including(graph: 'graph://member/1', database: 'member'))
        .and_return(member)
    end

    it 'renders active-members without crashing on a blank field' do
      get '/cbgp/active-members'

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('<nombre>Ada</nombre>')
      expect(last_response.body).to include('<cluster></cluster>')
    end

    it 'renders active-emails without crashing on a blank field' do
      get '/cbgp/active-emails'

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('<email>ada@example.org</email>')
    end
  end
end
