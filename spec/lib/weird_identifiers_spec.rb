# frozen_string_literal: true

require 'rack/test'
require_relative '../../app/controllers/application_controller'

# Nobody knows the naming convention of CBGP internal project codes, so assume
# the worst: spaces, slashes (funder codes like PID2020-113900RB-I00/AEI/10.13039/...),
# every regex metacharacter, quotes, backslashes, SPARQL/HTML/URL-significant
# punctuation, non-ASCII, and outright injection attempts. Every layer a
# project code passes through must carry it intact and safely: building a
# search/write query that still PARSES (not merely "contains"), saving it,
# matching it back from the commitment side, the pre-filled "add" link, and
# HTML rendering. The live-Virtuoso counterpart of this is run by hand
# (see the session notes); this spec needs no triple store.
WEIRD_CODES = [
  'PLAIN-1',
  'A/B 2026/001',
  'PID2020-113900RB-I00/AEI/10.13039/501100011033',
  'C(1)+[2]*3?',
  'a.b|c^d$e',
  'x{2,3}',
  'quote"inside',
  "it's",
  'back\\slash',
  'ends with backslash\\',
  'two\\\\backslashes',
  'back\\"quote',
  '<script>alert(1)</script>',
  '"><img src=x onerror=alert(1)>',
  'a&b=c&d=%41',
  '100% #1 ?x=y +plus',
  '  padded  ',
  'sp ace  double',
  'ünïcödé-ñ-€-日本-Ω',
  '#frag @at ;semi --dash /* c */',
  'x") } # DROP GRAPH <urn:x> ; (',
  "x' ) } UNION { ?s ?p ?o",
  '}{',
  '\\u0041\\n',
  # realistic identifiers issued by remote funders (European Commission, ERC, MSCA,
  # Spanish AEI/ISCIII/CAM...), which is what these fields are really filled with
  '101057811',
  'HORIZON-CL6-2022-FARM2FORK-01-02',
  'H2020-MSCA-ITN-2018-813872',
  'ERC-2019-COG-863991 (GA 863991)',
  'GA no. 101081234 / HORIZON-MSCA-2021-PF-01',
  'PID2019-108412GB-I00 / AEI / 10.13039/501100011033',
  'PCI2020-112127',
  'S2020/BIO-6350',
  'FP7-KBBE-2013-7-613817 [MAIZE-ADAPT]',
  'RTI2018-094567-B-I00; BIO2017-83480',
  'https://cordis.europa.eu/project/id/101057811',
  'doi:10.3030/101057811'
].freeze

# Every project field that holds an identifier or a funder's reference, not just the
# internal code: it is all free text typed in from remote conventions.
PROJECT_ID_FIELDS = %w[project_internal_code project_call_for_proposal_title].freeze

RSpec.describe 'project identifiers with arbitrary characters' do
  include Rack::Test::Methods

  def app
    CBGP::DatabasesApp
  end

  def commitment(id:, member: '12345678Z', project:, percentage: '50')
    ds = CBGP::Dataset.new(type: 'funding_commitment')
    ds.primary_id = id
    ds.member_nie = member
    ds.project_code = project
    ds.percentage = percentage
    ds.start_date = '2026-01-01'
    ds
  end

  PROJECT_ID_FIELDS.each do |field|
    describe "every identifier field: #{field}" do
      WEIRD_CODES.each do |code|
        it "searches, writes and saves #{code.inspect}" do
          q = build_search_query(search_params: { field => code }, dataset_type: 'european_research_project')
          expect { SPARQL.parse(q) }.not_to raise_error

          q_all = build_search_query(search_params: { field => code }, dataset_type: 'project')
          expect { SPARQL.parse(q_all) }.not_to raise_error

          params = { 'database' => 'project', 'primary_id' => '', 'project_title' => 'T', field => (field == 'project_internal_code' ? [code] : code) }
          dataset = nil
          allow(CBGP::Dataset).to receive(:write_dataset_to_db)
          allow(CBGP::Dataset).to receive(:get_primary_id).and_return(nil)
          begin
            dataset = CBGP::Dataset.load_from_params_and_write(params: params, form: 'european_research_project')
          rescue CBGP::Dataset::ValidationError
            dataset = nil # the form's other required fields aren't supplied here; the write query below is what matters
          end

          ds = CBGP::Dataset.new(type: 'european_research_project')
          ds.primary_id = 'rec-1'
          method = ds.fields.find { |f| f[:questionclass] == field }[:method]
          ds.public_send("#{method}=", field == 'project_internal_code' ? [code.strip] : code.strip)
          update = write_dataset_to_db_query(dataset: ds, form: 'european_research_project')[:query]
          expect { SPARQL.parse(update, update: true) }.not_to raise_error
          expect(Array(ds.public_send(method)).first).to eq(code.strip) unless code.strip.empty?
          expect(dataset).to be_nil.or be_a(CBGP::Dataset)
        end
      end
    end
  end

  WEIRD_CODES.each do |code|
    describe code.inspect do
      let(:stripped) { code.strip }

      it 'builds a parseable search query on the project\'s internal code' do
        q = build_search_query(search_params: { 'project_internal_code' => code }, dataset_type: 'project')
        expect(q).not_to be_nil
        expect { SPARQL.parse(q) }.not_to raise_error
      end

      it 'builds a parseable search query on the commitment\'s project field, with NOT too' do
        q = build_search_query(search_params: { 'commitment_project' => code, 'commitment_project__not' => '1' },
                               dataset_type: 'funding_commitment')
        expect { SPARQL.parse(q) }.not_to raise_error
      end

      it 'builds a parseable search query from a repeatable-field Array of it' do
        q = build_search_query(search_params: { 'project_internal_code' => [code, ''] }, dataset_type: 'project')
        expect { SPARQL.parse(q) }.not_to raise_error
      end

      it 'keeps the injection attempt inside the string literal (no stray clauses)' do
        q = build_search_query(search_params: { 'project_internal_code' => code }, dataset_type: 'project')
        parsed = SPARQL.parse(q)
        # a successful parse of a single SELECT is what proves nothing escaped the literal
        expect(parsed.class.name).to match(/Query|Operator|Project|Distinct/)
        expect(q.scan(/FILTER regex/).size).to eq(1)
      end

      it 'writes a record carrying it as a parseable update' do
        ds = CBGP::Dataset.new(type: 'personnel_project')
        ds.primary_id = 'rec-1'
        ds.title = 'T'
        ds.int_project_code = [stripped]
        update = write_dataset_to_db_query(dataset: ds, form: 'personnel_project')[:query]
        expect { SPARQL.parse(update, update: true) }.not_to raise_error
      end

      it 'saves a commitment that points at it, unchanged apart from trimming' do
        allow(CBGP::Dataset).to receive(:write_dataset_to_db)
        ds = CBGP::Dataset.load_from_params_and_write(
          params: { 'database' => 'commitment', 'primary_id' => '', 'commitment_member' => '12345678Z',
                    'commitment_project' => code, 'commitment_percentage' => '50', 'commitment_start_date' => '2026-01-01' },
          form: 'funding_commitment'
        )
        expect(ds.project_code).to eq(stripped)
      end

      it 'matches the commitment from the project\'s page (project panel) and the member page' do
        pr = CBGP::Dataset.new(type: 'personnel_project')
        pr.primary_id = 'p-1'
        pr.int_project_code = [stripped]
        mine = commitment(id: 'c-1', project: stripped)
        other = commitment(id: 'c-2', project: "#{stripped}X")

        allow(CBGP::RelatedRecords).to receive(:execute_search).and_return(%w[graph://c-1 graph://c-2])
        allow(CBGP::Dataset).to receive(:load_from_graph) do |*args, **kw|
          opts = kw.empty? ? args.last : kw
          { 'graph://c-1' => mine, 'graph://c-2' => other }[opts[:graph]]
        end
        allow(CBGP::Dataset).to receive(:fetch_reference_label) { |*args, **kw| (kw.empty? ? args.last : kw)[:value] }

        panel = CBGP::RelatedRecords.panels_for(entry: pr, type: 'project', as_of: Date.new(2026, 6, 1)).first

        # the search is loose (regex), so a near-miss ("<code>X") must be filtered out by the exact re-check
        expect(panel.rows.map(&:primary_id)).to eq(['c-1'])
        expect(panel.prefill).to eq('commitment_project' => stripped)
      end

      it 'round-trips through the pre-filled "add" link and renders it safely' do
        panel = CBGP::RelatedRecords::Panel.new(
          title: 'T', related_form: 'funding_commitment', related_form_label: 'Funding Commitment', columns: [], rows: [],
          total: BigDecimal(0), sum_label: nil, expected_total: nil, tolerance: nil, active_count: 0, warning: false,
          add_path: '/cbgp/dataset/funding_commitment', prefill: { 'commitment_project' => stripped }
        )
        url = panel.add_path + '?' + URI.encode_www_form(panel.prefill)
        expect(URI.decode_www_form(URI(url).query).to_h).to eq('commitment_project' => stripped)
      end

      it 'renders the add form pre-filled with it without letting it out of its HTML context' do
        header 'Host', 'localhost'
        post '/cbgp/login', username: 'test-admin', password: 'test'
        get '/cbgp/dataset/funding_commitment', 'commitment_project' => code

        expect(last_response.status).to eq(200)
        body = last_response.body
        expect(body).not_to include('<script>alert(1)</script>')
        expect(body).not_to include('<img src=x onerror=alert(1)>')
        expect(body).not_to match(/value="[^"]*"[^>]*onerror=/i)
        # the value is there, HTML-escaped, in the hidden input and the displayed <code>
        expect(body).to include(CGI.escapeHTML(stripped)) unless stripped.empty?
      end
    end
  end
end
