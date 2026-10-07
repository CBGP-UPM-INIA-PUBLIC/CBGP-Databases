# frozen_string_literal: true

require 'rack/test'
require_relative '../app/controllers/application_controller'

# "Today" next to date boxes.
#  * Search: a tick box beside each bound sends the WORD today, which the search reads as
#    the day it is run - a relative statement, so the results page says what it meant.
#  * Data entry: a "Today" button fills the box with the real date; a record can never be
#    saved holding the word.
# (today.js was checked in a real browser, headless Firefox; this suite has no browser.)
RSpec.describe 'today beside date boxes', type: :request do
  include Rack::Test::Methods

  def app
    CBGP::DatabasesApp
  end

  before do
    header 'Host', 'localhost'
    post '/cbgp/login', username: 'test-admin', password: 'test'
  end

  describe 'search_uses_today?' do
    it 'sees the keyword in a date range, in a list, and in any capitalisation' do
      expect(search_uses_today?('d' => { 'start' => '', 'end' => 'today' })).to be true
      expect(search_uses_today?('d' => ['x', ' Today '])).to be true
      expect(search_uses_today?('d' => 'TODAY')).to be true
    end

    it 'does not mistake other text for it' do
      expect(search_uses_today?('d' => { 'start' => '2026-01-01', 'end' => '' }, 't' => 'today is the day')).to be false
      expect(search_uses_today?({})).to be false
    end
  end

  describe 'the search form' do
    it 'has a today tick box beside both bounds of every date range, sharing the box\'s name' do
      get '/cbgp/search-dataset/project'
      body = last_response.body
      ticks = body.scan(/<input type="checkbox" name="([^"]+)\[(start|end)\]" value="today" data-date-input="([^"]+)"/)

      expect(ticks).not_to be_empty
      expect(ticks.map { |q, _b, _id| q }.uniq.size * 2).to eq(ticks.size)
      ticks.each do |_q, bound, input_id|
        expect(input_id).to end_with("_#{bound}")
        expect(body).to include("id=\"#{input_id}\"")
      end
    end

    it 'loads the script that greys out the date box while the tick box is ticked' do
      get '/cbgp/search-dataset/project'
      expect(last_response.body).to include('/js/today.js')
      expect(File.read(File.expand_path('../app/public/js/today.js', __dir__))).to include('data-date-input')
    end
  end

  describe 'the results page' do
    before do
      allow_any_instance_of(CBGP::DatabasesApp).to receive(:execute_search).and_return([])
    end

    it 'says what today was read as, and that it is not a fixed date' do
      get '/cbgp/query-dataset/project', 'project_start_date' => { 'start' => '', 'end' => 'today' }

      expect(last_response.body).to include(Date.today.iso8601)
      expect(last_response.body).to include('not a fixed date')
    end

    it 'says nothing of the kind for a search with real dates' do
      get '/cbgp/query-dataset/project', 'project_start_date' => { 'start' => '2026-01-01', 'end' => '2026-12-31' }

      expect(last_response.body).not_to include('not a fixed date')
    end
  end

  describe 'data entry' do
    it 'has a Today button that fills the date box in' do
      get '/cbgp/dataset/personnel_project'
      body = last_response.body

      expect(body).to include('data-fill-today')
      expect(body).to include('/js/today.js')
      expect(File.read(File.expand_path('../app/public/js/today.js', __dir__))).to include("input[type=\"date\"]")
    end

    it 'never saves the word: only a real date is accepted for a date field' do
      ds = CBGP::Dataset.new(type: 'personnel_project')
      expect { ds.coerce_value('today', 'date', 'Single') }.to raise_error(ArgumentError)
      expect(ds.coerce_value('2026-10-07', 'date', 'Single')).to eq('2026-10-07')
    end
  end
end
