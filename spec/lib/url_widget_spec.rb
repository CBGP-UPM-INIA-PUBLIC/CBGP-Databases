# frozen_string_literal: true

require 'rack/test'
require_relative '../../app/controllers/application_controller'

# The Application URL field (project_application_url): the admin team want the
# FULL link to the call (e.g. the European Commission Funding & Tenders topic
# page), not the call identifier. So the URL widget must (1) accept real-world
# funder URLs, (2) refuse anything that is not a complete http(s) address -
# including a bare identifier, which is never "fixed up" into a URL - and
# (3) show stored values as links without ever letting stored text become
# markup or a javascript: link.
RSpec.describe 'URL widget' do
  EC_URL = 'https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/opportunities/topic-details/' \
           'HORIZON-CL5-2027-07-D3-26?isExactMatch=true&status=31094501,31094502,31094503&' \
           'callIdentifier=HORIZON-CL5-2027-07&order=DESC&pageNumber=1&pageSize=50&sortBy=startDate'

  GOOD_URLS = [
    EC_URL,
    'https://cordis.europa.eu/project/id/101057811',
    'http://example.org',
    'HTTPS://EXAMPLE.ORG/Path',
    'https://www.aei.gob.es/convocatorias/buscador-convocatorias?field=a&sort[0]=b|c',
    'https://example.org/a_(b)/c?q=1%202&r=%C3%B1#frag',
    'https://example.org/ñandú/日本?q=ü',
    'https://example.org:8443/x',
    'https://user@example.org/x',
    'https://10.13039.example.org/doi/10.13039/501100011033',
    '  https://example.org/padded  '
  ].freeze

  BAD_URLS = [
    'HORIZON-CL5-2027-07-D3-26',            # the identifier on its own - exactly what must NOT be accepted
    'www.example.org',
    'example.org/call',
    '//example.org/x',
    'https://',
    'https:///nohost',
    'http://',
    'javascript:alert(1)',
    'JaVaScRiPt:alert(1)',
    'data:text/html,<script>alert(1)</script>',
    'ftp://example.org/file',
    'mailto:someone@example.org',
    'file:///etc/passwd',
    'https://exa mple.org/x',
    "https://example.org/x\nSet-Cookie: a=b",
    "https://example.org/x\ty",
    'https://example.org/"onmouseover="alert(1)',
    'https://example.org/<script>alert(1)</script>',
    "https://example.org/x'>\\",
    'https://example.org/`x`',
    'https://' + ('a' * 2100) + '.org',
    '   ',
    '',
    'see the Commission website'
  ].freeze

  describe 'parse_http_url / valid_http_url?' do
    GOOD_URLS.each do |url|
      it "accepts #{url[0, 70].inspect}" do
        expect(valid_http_url?(url)).to be(true)
      end
    end

    BAD_URLS.each do |url|
      it "rejects #{url[0, 70].inspect}" do
        expect(valid_http_url?(url)).to be(false)
      end
    end

    it 'handles nil' do
      expect(valid_http_url?(nil)).to be(false)
    end
  end

  describe 'coerce_value for the url class' do
    let(:ds) { CBGP::Dataset.new(type: 'european_research_project') }

    it 'stores the address exactly as typed (trimmed) - nothing is rewritten' do
      expect(ds.coerce_value("  #{EC_URL}  ", 'url', 'Single')).to eq(EC_URL)
    end

    it 'raises a message that tells the user what to do, for a bare identifier' do
      expect { ds.coerce_value('HORIZON-CL5-2027-07-D3-26', 'url', 'Single') }
        .to raise_error(ArgumentError, /not a full web address.*http:\/\/ or https:\/\/.*not just an identifier/m)
    end

    it 'validates every value of a repeatable url field' do
      expect(ds.coerce_value(['https://a.org', ' ', 'https://b.org'], 'url', 'Multiple')).to eq(%w[https://a.org https://b.org])
      expect { ds.coerce_value(['https://a.org', 'nope'], 'url', 'Multiple') }.to raise_error(ArgumentError)
    end

    it 'leaves other classes unaffected' do
      expect(ds.coerce_value('not a url', 'string', 'Single')).to eq('not a url')
    end
  end

  describe 'url_link_html' do
    it 'makes a safe new-tab link for a good address' do
      html = url_link_html('https://example.org/a?b=1&c=2')
      expect(html).to eq('<a href="https://example.org/a?b=1&amp;c=2" target="_blank" rel="noopener noreferrer">https://example.org/a?b=1&amp;c=2</a>')
    end

    it 'can show shorter link text while linking the whole address' do
      expect(url_link_html(EC_URL, 'short')).to include("href=\"#{CGI.escapeHTML(EC_URL)}\"", '>short</a>')
    end

    ['javascript:alert(1)', '"><script>alert(1)</script>', "x\" onmouseover=\"y", 'not a url <b>bold</b>'].each do |bad|
      it "never makes a link or markup from stored text #{bad.inspect}" do
        html = url_link_html(bad)
        expect(html).not_to include('<a ')
        expect(html).not_to match(/<(script|b)\b/)
      end
    end
  end

  describe 'the Application URL field' do
    %w[european_research_project national_regional_research_project private_research_project personnel_project].each do |form|
      it "is a required URL field on #{form}" do
        field = CBGP::Dataset.fields_for(form).find { |f| f[:questionclass] == 'project_application_url' }
        expect(field).not_to be_nil
        expect(field[:class]).to eq('url')
        expect(field[:widget]).to end_with('#url')
        expect(CBGP::Dataset.form_required_fields(form: form)).to include('project_application_url')
      end
    end

    it 'is required on EVERY form that shows it - admin and user-facing alike' do
      forms = get_questionnaire_types_query(type: 'Core') + get_questionnaire_types_query(type: 'UserFacing')
      names = forms.map { |f| f[:questionnaire_type].to_s.split('#').last }
      showing = names.select { |f| CBGP::Dataset.fields_for(f).any? { |x| x[:questionclass] == 'project_application_url' } }

      expect(showing).to include('userproject', 'european_research_project', 'personnel_project')
      showing.each do |form|
        expect(CBGP::Dataset.form_required_fields(form: form)).to include('project_application_url'), "#{form} shows the field but does not require it"
      end
    end

    it 'cannot be left blank on the user-facing project form (the path the User portal saves through)' do
      allow(CBGP::Dataset).to receive(:get_primary_id).and_return(nil)
      allow(CBGP::Dataset).to receive(:write_dataset_to_db)
      params = { 'database' => 'project', 'primary_id' => '', 'project_title' => 'T' }

      expect { CBGP::Dataset.load_from_params_and_write(params: params, form: 'userproject') }
        .to raise_error(CBGP::Dataset::ValidationError) { |e| expect(e.errors.map { |x| x[:message] }).to include('Application URL is required') }
      # (the user form also requires the PI, so a submission always says who is responsible)
      expect { CBGP::Dataset.load_from_params_and_write(params: params.merge('project_application_url' => 'https://example.org/call', 'project_pi_nie' => ['12345678Z']), form: 'userproject') }
        .not_to raise_error
    end

    it 'cannot be left blank on any admin project form either' do
      allow(CBGP::Dataset).to receive(:get_primary_id).and_return(nil)
      %w[european_research_project national_regional_research_project private_research_project personnel_project].each do |form|
        expect { CBGP::Dataset.load_from_params_and_write(params: { 'database' => 'project', 'primary_id' => '', 'project_title' => 'T' }, form: form) }
          .to raise_error(CBGP::Dataset::ValidationError) { |e| expect(e.errors.map { |x| x[:message] }).to include('Application URL is required') }
      end
    end

    it 'shows the required marker on the form' do
      q = Questionnaire.new(questionnaire_type: 'userproject')
      question = q.sections.flat_map(&:questions).find { |x| x.questionid == 'project_application_url' }
      expect(question.required).to be true
    end

    it 'no longer exists under its old name' do
      expect(CBGP::Dataset.fields_for('european_research_project').map { |f| f[:questionclass] }).not_to include('project_application_code')
    end

    it 'rejects a form save that gives only the call identifier' do
      allow(CBGP::Dataset).to receive(:get_primary_id).and_return(nil)
      allow(CBGP::Dataset).to receive(:write_dataset_to_db)
      params = { 'database' => 'project', 'primary_id' => '', 'project_title' => 'T', 'project_application_url' => 'HORIZON-CL5-2027-07-D3-26' }
      expect { CBGP::Dataset.load_from_params_and_write(params: params, form: 'personnel_project') }
        .to raise_error(CBGP::Dataset::ValidationError) do |e|
          expect(e.errors.map { |x| x[:label] }).to include('Application URL')
          expect(e.errors.find { |x| x[:label] == 'Application URL' }[:message]).to match(/full web address/)
        end
    end
  end

  describe 'on the pages', type: :request do
    include Rack::Test::Methods

    def app
      CBGP::DatabasesApp
    end

    before do
      header 'Host', 'localhost'
      post '/cbgp/login', username: 'test-admin', password: 'test'
    end

    it 'renders a real URL input on the add form' do
      get '/cbgp/dataset/european_research_project'
      expect(last_response.body).to match(/<input type="url" name="project_application_url"[^>]*placeholder="https:\/\/\.\.\."/)
    end

    it 'shows the stored address in the edit form escaped, with an open-link beside it' do
      entry = CBGP::Dataset.new(type: 'european_research_project')
      entry.primary_id = 'p-1'
      entry.application_url = 'https://example.org/a?b=1&c=2'
      allow(CBGP::Dataset).to receive(:load_from_primary_id).and_return(entry)
      allow(CBGP::RelatedRecords).to receive(:panels_for).and_return([])

      get '/cbgp/dataset/european_research_project/p-1'

      expect(last_response.body).to include('value="https://example.org/a?b=1&amp;c=2"')
      expect(last_response.body).to include('href="https://example.org/a?b=1&amp;c=2" target="_blank" rel="noopener noreferrer"')
    end

    it 'does not turn a hostile stored value into a link or markup in the edit form' do
      entry = CBGP::Dataset.new(type: 'european_research_project')
      entry.primary_id = 'p-1'
      entry.set_raw(CBGP::Dataset.fields_for('european_research_project').find { |f| f[:questionclass] == 'project_application_url' }[:q],
                    '"><script>alert(1)</script>')
      allow(CBGP::Dataset).to receive(:load_from_primary_id).and_return(entry)
      allow(CBGP::RelatedRecords).to receive(:panels_for).and_return([])

      get '/cbgp/dataset/european_research_project/p-1'

      expect(last_response.body).not_to include('"><script>alert(1)</script>')
    end

    it 'shows URLs as links (and other stored text escaped) in search results' do
      entry = CBGP::Dataset.new(type: 'european_research_project')
      entry.primary_id = 'p-1'
      entry.application_url = EC_URL
      entry.title = '<b>bold</b>'
      allow_any_instance_of(CBGP::DatabasesApp).to receive(:execute_search).and_return(['graph://p-1'])
      allow_any_instance_of(CBGP::DatabasesApp).to receive(:batch_retrieve_dataset_ids).and_return('graph://p-1' => 'p-1')
      allow_any_instance_of(CBGP::DatabasesApp).to receive(:fetch_datasets_raw_data).and_return([])
      allow(CBGP::Dataset).to receive(:load_from_graph).and_return(entry)

      post '/cbgp/query-dataset/european_research_project', 'project_title' => 'x'

      body = last_response.body
      expect(body).to include("href=\"#{CGI.escapeHTML(EC_URL)}\" target=\"_blank\" rel=\"noopener noreferrer\"")
      expect(body).to include('...</a>') # long address shortened as text, full address as the target
      expect(body).not_to include('<b>bold</b>')
      expect(body).to include('&lt;b&gt;bold&lt;/b&gt;')
    end

    it 'filters a URL field with a plain text box' do
      get '/cbgp/search-dataset/european_research_project'
      expect(last_response.body).to include('placeholder="Enter part of the web address to filter"')
    end
  end
end
