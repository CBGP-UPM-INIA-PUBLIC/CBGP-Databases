# frozen_string_literal: true

require 'rack/test'
require_relative '../app/controllers/application_controller'

# Found 2026-10-06: a link from a search of the shared dbname ("project")
# opened /cbgp/dataset/project/<id> - an edit page carrying the fields of
# EVERY form that shares that dbname (personnel data on a research project and
# vice versa), whose hidden form_class was empty, so saving it would have
# stamped the record with the dbname instead of its real form and dropped it
# out of that form's searches. An edit page must open under the form that
# wrote the record (its dcterms:type stamp), whatever name the URL used.
RSpec.describe 'the edit page opens under the record\'s own form', type: :request do
  include Rack::Test::Methods

  def app
    CBGP::DatabasesApp
  end

  let(:entry) do
    ds = CBGP::Dataset.new(type: 'personnel_project')
    ds.primary_id = 'p-1'
    ds
  end

  before do
    header 'Host', 'localhost'
    post '/cbgp/login', username: 'test-admin', password: 'test'
    allow(CBGP::Dataset).to receive(:load_from_primary_id).and_return(entry)
    allow(CBGP::RelatedRecords).to receive(:panels_for).and_return([])
  end

  def stamp(form)
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:get_record_form).and_return(form)
  end

  it 'redirects the shared-dbname URL to the record\'s true form' do
    stamp('personnel_project')
    get '/cbgp/dataset/project/p-1'

    expect([301, 302, 303, 307]).to include(last_response.status)
    expect(URI(last_response.headers['Location']).path).to eq('/cbgp/dataset/personnel_project/p-1')
  end

  it 'redirects a wrong-form URL the same way' do
    stamp('personnel_project')
    get '/cbgp/dataset/european_research_project/p-1'

    expect(URI(last_response.headers['Location']).path).to eq('/cbgp/dataset/personnel_project/p-1')
  end

  it 'shows the page, with that form\'s fields only, when the URL already names the true form' do
    stamp('personnel_project')
    get '/cbgp/dataset/personnel_project/p-1'

    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('/cbgp/validate-dataset/personnel_project')
  end

  it 'encodes the identifier in the redirect' do
    stamp('personnel_project')
    get '/cbgp/dataset/project/a%20b%26c'

    expect(URI(last_response.headers['Location']).path).to eq('/cbgp/dataset/personnel_project/a%20b%26c')
  end

  it 'opens a record that has no stamp (an old one) as before' do
    stamp(nil)
    get '/cbgp/dataset/personnel_project/p-1'

    expect(last_response.status).to eq(200)
  end

  it 'ignores a stamp naming a form that no longer exists, rather than redirecting to a dead page' do
    stamp('no_such_form')
    get '/cbgp/dataset/personnel_project/p-1'

    expect(last_response.status).to eq(200)
  end
end

RSpec.describe 'get_record_form' do
  it 'reads the form class from the stamp on the record\'s graph' do
    allow(self).to receive(:retrieve_dataset_graph_query).and_return([{ g: RDF::URI('https://example.org/g/1') }])
    allow(DATABASE).to receive(:query) do |q|
      expect(q).to include('<https://example.org/g/1> dcterms:type ?form')
      [{ form: RDF::URI('https://w3id.org/CBGP-App#personnel_project') }]
    end

    expect(get_record_form(primary_id: 'p-1')).to eq('personnel_project')
  end

  it 'is nil for a record with no stamp, or one that cannot be found' do
    allow(self).to receive(:retrieve_dataset_graph_query).and_return([{ g: RDF::URI('https://example.org/g/1') }])
    allow(DATABASE).to receive(:query).and_return([])
    expect(get_record_form(primary_id: 'p-1')).to be_nil

    allow(self).to receive(:retrieve_dataset_graph_query).and_return([])
    expect(get_record_form(primary_id: 'nope')).to be_nil
  end

  it 'is nil rather than an exception when the store does not answer' do
    allow(self).to receive(:retrieve_dataset_graph_query).and_raise('down')
    expect(get_record_form(primary_id: 'p-1')).to be_nil
  end
end
