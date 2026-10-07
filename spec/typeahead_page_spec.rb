# frozen_string_literal: true

require 'rack/test'
require_relative '../app/controllers/application_controller'

# The lookup boxes (cross-reference fields, e.g. the PI on the member-facing
# project form) used an HTML <datalist>. The browser filters a datalist by the
# literal text typed, so "Alarco" hid "Alarcón Moreno" although the server,
# which ignores accents, had just found it; and a datalist can only hand back
# the text of a row, so two people with the same label could not be told apart.
# They now use app/public/js/typeahead.js. (The script's behaviour was checked
# in a real browser - Firefox, headless - with typed text, keyboard choice and
# two identically-labelled rows; there is no browser test in this suite.)
RSpec.describe 'lookup boxes', type: :request do
  include Rack::Test::Methods

  def app
    CBGP::DatabasesApp
  end

  before { header 'Host', 'localhost' }

  def sign_in(user)
    post '/cbgp/login', username: user, password: 'test'
  end

  it 'ships the suggestion-list script' do
    script = File.read(File.expand_path('../app/public/js/typeahead.js', __dir__))
    expect(script).to include('CBGPSuggest')
    expect(script).to include('attach')
  end

  %w[test-admin test-user].each do |login|
    context "for #{login}" do
      before { sign_in(login) }

      it 'loads the script on the page and builds the lookup with it, not with a datalist' do
        get '/cbgp/dataset/user-database/userproject'

        expect(last_response.status).to eq(200)
        body = last_response.body
        expect(body).to include('/js/typeahead.js')
        expect(body).to include('CBGPSuggest.attach')
        expect(body).not_to include('<datalist')
        expect(body).not_to match(/\blist="[^"]*_suggestions/)
      end

      it 'serves the script' do
        get '/js/typeahead.js'
        expect(last_response.status).to eq(200)
      end
    end
  end

  describe 'the suggestions it is fed' do
    before { sign_in('test-user') }

    it 'returns each person as {value, label} with the label already carrying the first name' do
      allow(CBGP::Dataset).to receive(:fetch_reference_suggestions)
        .and_return([{ value: '1', label: 'Alarcón Moreno, Pablo' }, { value: '2', label: 'Alarcón Moreno, Sara' }])

      get '/cbgp/reference/suggest/member', q: 'Alarco', via: 'member_dni_nie_pas', label_method: 'member_surnames'

      expect(JSON.parse(last_response.body)).to eq([{ 'value' => '1', 'label' => 'Alarcón Moreno, Pablo' },
                                                    { 'value' => '2', 'label' => 'Alarcón Moreno, Sara' }])
    end

    it 'passes the typed text to the search unchanged, accents or none (matching ignores them server-side)' do
      expect(CBGP::Dataset).to receive(:fetch_reference_suggestions)
        .with(hash_including(search_query: 'Alarcó')).and_return([])
      get '/cbgp/reference/suggest/member', q: 'Alarcó', via: 'member_dni_nie_pas', label_method: 'member_surnames'
      expect(last_response.status).to eq(200)
    end
  end
end
