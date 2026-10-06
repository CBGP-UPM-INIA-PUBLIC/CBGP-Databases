# frozen_string_literal: true

require 'rack/test'
require_relative '../app/controllers/application_controller'

# Renders the real admin edit page (dataset.erb + _related_records.erb) for a
# saved record whose form declares a related-records panel, with the triple
# store stubbed out. The panel logic itself is covered in
# spec/lib/related_records_spec.rb; this only checks the template wiring and
# that nothing read from stored data reaches the page unescaped.
RSpec.describe 'related-records panel on the edit page', type: :request do
  include Rack::Test::Methods

  def app
    CBGP::DatabasesApp
  end

  def login_as_admin
    header 'Host', 'localhost'
    post '/cbgp/login', username: 'test-admin', password: 'test'
  end

  let(:entry) do
    ds = CBGP::Dataset.new(type: 'member')
    ds.primary_id = 'm-1'
    ds
  end

  def panel(rows:, warning: false)
    CBGP::RelatedRecords::Panel.new(
      title: 'Funding commitments', related_form: 'funding_commitment', related_form_label: 'Funding Commitment',
      columns: ['Project', 'Percentage'], rows: rows, total: BigDecimal('70'), sum_label: 'Percentage',
      expected_total: BigDecimal('100'), tolerance: BigDecimal('0.05'), active_count: rows.count(&:active),
      warning: warning, add_path: '/cbgp/dataset/funding_commitment',
      prefill: { 'commitment_member' => '12345678Z' }
    )
  end

  before do
    allow(CBGP::Dataset).to receive(:load_from_primary_id).and_return(entry)
    allow_any_instance_of(CBGP::DatabasesApp).to receive(:get_record_form).and_return(nil) # no live store in specs
    login_as_admin
  end

  it 'lists related rows with a link to each, and the warning when the total is off' do
    row = CBGP::RelatedRecords::Row.new(primary_id: 'c-1', cells: ['My project', '70,00'], active: true)
    allow(CBGP::RelatedRecords).to receive(:panels_for).and_return([panel(rows: [row], warning: true)])

    get '/cbgp/dataset/member/m-1'

    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Funding commitments', 'My project', '70,00')
    expect(last_response.body).to include('href="/cbgp/dataset/funding_commitment/c-1"')
    expect(last_response.body).to include('related-records-warning')
    expect(last_response.body).to include('href="/cbgp/dataset/funding_commitment?commitment_member=12345678Z"')
    expect(last_response.body).to include('Add a new Funding Commitment</a>')
  end

  it 'omits the warning block when the panel does not carry one' do
    row = CBGP::RelatedRecords::Row.new(primary_id: 'c-1', cells: ['P', '100,00'], active: true)
    allow(CBGP::RelatedRecords).to receive(:panels_for).and_return([panel(rows: [row])])

    get '/cbgp/dataset/member/m-1'

    expect(last_response.body).not_to include('related-records-warning')
  end

  it 'says so when there are no related records' do
    allow(CBGP::RelatedRecords).to receive(:panels_for).and_return([panel(rows: [])])

    get '/cbgp/dataset/member/m-1'

    expect(last_response.body).to include('None yet.')
  end

  it 'escapes stored values rather than injecting them into the page' do
    evil = '<script>alert(1)</script>'
    row = CBGP::RelatedRecords::Row.new(primary_id: 'c-1', cells: [evil, 'x'], active: true)
    allow(CBGP::RelatedRecords).to receive(:panels_for).and_return([panel(rows: [row])])

    get '/cbgp/dataset/member/m-1'

    expect(last_response.body).not_to include(evil)
    # Rack::Utils.escape_html also entity-encodes the slash
    expect(last_response.body).to include('&lt;script&gt;alert(1)&lt;&#x2F;script&gt;')
  end

  it 'turns each lookup-able cell after the first into an exact-match search link on the stored value' do
    fields = [{ questionclass: 'commitment_project', widget: 'text', class: 'string' },
              { questionclass: 'commitment_funder', widget: 'text', class: 'string' },
              { questionclass: 'commitment_percentage', widget: 'number', class: 'number' },
              { questionclass: 'commitment_start_date', widget: 'date', class: 'date' }]
    row = CBGP::RelatedRecords::Row.new(
      primary_id: 'c-1', cells: ['My project', 'Funder X', '70,00', '2026-01-01'], active: true,
      values: [[['P-1', 'My project']], [['F-1', 'Funder X']], [['70', '70,00']], [['2026-01-01', '2026-01-01']]]
    )
    pnl = panel(rows: [row])
    pnl.fields = fields
    allow(CBGP::RelatedRecords).to receive(:panels_for).and_return([pnl])

    get '/cbgp/dataset/member/m-1'

    expect(last_response.body).to include(
      'href="/cbgp/dataset/funding_commitment/c-1"', # the first cell still opens the record itself
      'href="/cbgp/query-dataset/funding_commitment?commitment_funder=F-1&amp;commitment_funder__exact=1"',
      '>Funder X</a>'
    )
    expect(last_response.body).not_to include('commitment_project=P-1') # no search link in the record-link cell
    expect(last_response.body).not_to include('commitment_percentage=', 'commitment_start_date=') # numbers, dates: plain
    expect(last_response.body).to include('70,00', '2026-01-01')
  end

  it 'prints a later cell as plain escaped text when the panel carries no field descriptors' do
    row = CBGP::RelatedRecords::Row.new(primary_id: 'c-1', cells: ['P', '<i>x</i>'], active: true)
    allow(CBGP::RelatedRecords).to receive(:panels_for).and_return([panel(rows: [row])])

    get '/cbgp/dataset/member/m-1'

    expect(last_response.body).to include('&lt;i&gt;x&lt;&#x2F;i&gt;')
    # only the panel is meant here: the edit page itself carries search arrows beside its own fields
    panel_html = last_response.body[/<div class="related-records">.*?<\/table>/m]
    expect(panel_html).not_to be_nil
    expect(panel_html).not_to include('search-link')
  end

  it 'renders nothing extra for a form with no panels' do
    allow(CBGP::RelatedRecords).to receive(:panels_for).and_return([])

    get '/cbgp/dataset/member/m-1'

    expect(last_response.status).to eq(200)
    expect(last_response.body).not_to include('class="related-records"')
  end

  it 'also shows the panel on the page returned right after a successful save' do
    row = CBGP::RelatedRecords::Row.new(primary_id: 'c-1', cells: ['My project', '70,00'], active: true)
    allow(CBGP::Dataset).to receive(:load_from_params_and_write).and_return(entry)
    allow(CBGP::Triggers).to receive(:check_and_fire)
    allow(CBGP::RelatedRecords).to receive(:panels_for).and_return([panel(rows: [row])])

    post '/cbgp/validate-dataset/member', 'form_class' => 'member', 'primary_id' => ''

    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Funding commitments', 'My project')
  end

  describe 'the search form' do
    it 'offers the name typeahead (not a bare text box) for cross-reference fields' do
      get '/cbgp/search-dataset/personnel_project'

      expect(last_response.status).to eq(200)
      # xref widget markup: searches by label, posts the stored key
      %w[beneficiary_nie personnel_project_responsible_pi_nie project_dni_nie_pas].each do |qid|
        expect(last_response.body).to include("id=\"#{qid}_container\"")
      end
      expect(last_response.body).to include('xref-row')
    end

    it 'still renders ordinary fields as plain filters' do
      get '/cbgp/search-dataset/personnel_project'

      expect(last_response.body).to include('id="project_title_ANSWER"')
    end
  end

  describe 'prefilling a new record from the add link' do
    it 'fills the cross-reference field named in the query string, and ignores plain fields' do
      get '/cbgp/dataset/funding_commitment', 'commitment_member' => '12345678Z', 'commitment_notes' => 'sneaky'

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('12345678Z')
      expect(last_response.body).not_to include('sneaky')
    end

    it 'is harmless with a junk value or no parameters' do
      get '/cbgp/dataset/funding_commitment', 'commitment_member' => '"><script>x</script>'
      expect(last_response.status).to eq(200)
      expect(last_response.body).not_to include('<script>x</script>')
    end
  end

  describe 'the cross-reference search box hint' do
    it 'says what is searched and that it needs 2 characters, from the ontology\'s own field labels' do
      get '/cbgp/dataset/funding_commitment'

      body = last_response.body
      expect(body).to include('Type at least 2 characters of the Surname(s) to search existing member...')
      # the project box's target has no name of its own in the ontology (a bare storage name), so none is shown
      expect(body).to include('Type at least 2 characters of the Title of the project to search...')
    end

    it 'is the same on the search form' do
      get '/cbgp/search-dataset/funding_commitment'

      expect(last_response.body).to include('Type at least 2 characters of the Surname(s) to search existing member...')
    end

    it 'also reaches the "add another" row of a repeatable cross-reference' do
      get '/cbgp/dataset/national_regional_research_project'

      expect(last_response.body).to include('const xrefHint   = "Type at least 2 characters of the Surname(s) to search existing member..."')
      expect(last_response.body).to include('placeholder="${xrefHint}"')
    end
  end
end
