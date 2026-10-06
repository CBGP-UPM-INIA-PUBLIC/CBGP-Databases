# frozen_string_literal: true

require 'rack/test'
require 'cgi'
require_relative '../app/controllers/application_controller'

# On the edit page an admin gets, beside each field's label, an arrow that
# opens - in a new window - the same exact-match search the results page links
# to, for the value the record STORES (not whatever is being typed). Same
# rules as the results page (search_link_html): prose, numbers, dates and
# URLs get no arrow. Non-admins never see them.
RSpec.describe 'search arrows on the edit page', type: :request do
  include Rack::Test::Methods

  def app
    CBGP::DatabasesApp
  end

  def login(username)
    header 'Host', 'localhost'
    post '/cbgp/login', username: username, password: 'test'
  end

  def set(entry, questionclass, value)
    field = entry.fields.find { |f| f[:questionclass] == questionclass }
    raise "no field #{questionclass}" unless field

    entry.public_send("#{field[:method]}=", value)
  end

  let(:entry) do
    ds = CBGP::Dataset.new(type: 'funding_commitment')
    ds.primary_id = 'c-1'
    set(ds, 'commitment_member', '00831666D')
    set(ds, 'commitment_project', 'P&Q <1>')
    set(ds, 'commitment_percentage', '60.00')
    set(ds, 'commitment_start_date', '2026-01-01')
    set(ds, 'commitment_notes', 'some prose')
    ds
  end

  let(:arrows) do
    last_response.body.scan(%r{<span class="field-search-links">(.*?)</span>}m).flatten.join(' ')
  end

  before do
    allow(CBGP::Dataset).to receive(:load_from_primary_id).and_return(entry)
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:get_record_form).and_return(nil) # no live store in specs
    allow(CBGP::RelatedRecords).to receive(:panels_for).and_return([])
  end

  context 'as an admin' do
    before do
      login('test-admin')
      get '/cbgp/dataset/funding_commitment/c-1'
    end

    it 'renders the page' do
      expect(last_response.status).to eq(200)
    end

    it 'adds a new-window arrow to the search for each stored, linkable value' do
      expect(arrows).to include('target="_blank"', 'rel="noopener noreferrer"', ">↗</a>")
    end

    it 'sends a cross-reference value to the referenced record (the member), by key' do
      expect(CGI.unescapeHTML(arrows)).to include(
        '/cbgp/query-dataset/member?member_dni_nie_pas=00831666D&member_dni_nie_pas__exact=1'
      )
    end

    it 'sends a second cross-reference (the project) to its key field, escaping what the value contains' do
      href = CGI.unescapeHTML(arrows)[%r{href="(/cbgp/query-dataset/project\?[^"]*)"}, 1]
      expect(href).not_to be_nil
      expect(Rack::Utils.parse_query(URI(href).query)).to include('project_internal_code' => 'P&Q <1>',
                                                                  'project_internal_code__exact' => '1')
      expect(arrows).not_to include('P&Q <1>')
    end

    it 'adds none for numbers, dates and prose' do
      expect(arrows).not_to include('commitment_percentage', 'commitment_start_date', 'commitment_notes')
    end

    it 'describes each arrow for assistive technology' do
      expect(arrows).to match(/aria-label="Find records with .* \(opens in a new window\)"/)
    end
  end

  context 'on a record with nothing stored in a field' do
    it 'adds no arrow for it' do
      set(entry, 'commitment_member', '')
      set(entry, 'commitment_project', '')
      login('test-admin')
      get '/cbgp/dataset/funding_commitment/c-1'

      expect(arrows.gsub(/\s/, '')).to eq('')
    end
  end

  context 'as a non-admin' do
    it 'shows no arrows at all' do
      login('test-user')
      get '/cbgp/dataset/funding_commitment/c-1'

      expect(last_response.status).to eq(200)
      expect(last_response.body).not_to include('field-search-links')
      expect(last_response.body).not_to include('/cbgp/query-dataset/member?')
    end
  end
end

RSpec.describe 'field_search_links_html' do
  let(:text_field) { { questionclass: 'member_name', widget: 'text', class: 'string' } }

  it 'makes one arrow per stored value of a repeatable field and skips blank rows' do
    html = field_search_links_html(field: text_field, database: 'member', values: ['A', '', 'B'])
    expect(html.scan('<a ').size).to eq(2)
    expect(html).to include('member_name=A', 'member_name=B')
  end

  it 'is empty for a field that is not a link, or for no value' do
    expect(field_search_links_html(field: text_field.merge(widget: 'textfield'), database: 'member', values: 'x')).to eq('')
    expect(field_search_links_html(field: text_field, database: 'member', values: nil)).to eq('')
  end

  it 'never raises into the page it decorates' do
    allow(self).to receive(:search_link_html).and_raise('boom')
    expect(field_search_links_html(field: text_field, database: 'member', values: 'x')).to eq('')
  end
end
