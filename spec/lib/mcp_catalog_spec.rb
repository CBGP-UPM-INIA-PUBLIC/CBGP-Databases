# frozen_string_literal: true

# What the model is told about the DATA comes from the ontology's own
# descriptions (rdfs:comment on the forms class and on each form). These specs
# read the real ontology, so they also guard the ontology: a form added
# without a description in both languages fails here, not in front of a user.
RSpec.describe Mcp::Catalog do
  before { described_class.reset! }
  after { described_class.reset! }

  let(:ctx) { Mcp::Records::Context.new }

  describe 'the ontology the specs read' do
    it 'describes the dataset, in both languages' do
      %w[en es].each do |lang|
        Thread.current[:language] = lang
        expect(Mcp::Records::Context.new.dataset_description.to_s.length).to be > 40, "no dataset description in #{lang}"
      end
    end

    it 'describes every listed form, in both languages, with a first sentence that stands alone' do
      %w[en es].each do |lang|
        Thread.current[:language] = lang
        Mcp::Records::Context.new.forms.each do |form|
          expect(form.description.to_s.length).to be > 20, "#{form.name} has no description in #{lang}"
          expect(described_class.first_sentence(form.description)).not_to end_with('…'), "#{form.name}: first sentence too long in #{lang}"
        end
      end
    end

    it 'says which everyday words mean the member form' do
      expect(ctx.forms.find { |f| f.name == 'member' }.description).to match(/employees/i)
    end
  end

  describe 'which forms are offered' do
    it 'lists the staff-facing data forms and leaves out member-facing submission forms' do
      names = ctx.forms.map(&:name)
      expect(names).to include('member', 'publication', 'funding_commitment')
      expect(names).not_to include('userproject')
      expect(ctx.forms.map(&:category).uniq).to eq([Mcp::Records::LISTED_CATEGORY])
    end

    it 'still resolves an unlisted form named in a record, so a returned id never dead-ends' do
      expect(ctx.form!('userproject').name).to eq('userproject')
      expect(ctx.forms.map(&:name)).not_to include('userproject')
    end
  end

  describe '.first_sentence' do
    it 'takes the first sentence only' do
      expect(described_class.first_sentence('People who work here. More detail. Even more.')).to eq('People who work here.')
    end

    it 'keeps a colon list, which carries the synonyms' do
      text = 'People: employees, staff and visitors, one record each.'
      expect(described_class.first_sentence(text)).to eq(text)
    end

    it 'cuts a very long sentence at a word and marks it' do
      cut = described_class.first_sentence("#{'word ' * 100}end.", 50)
      expect(cut).to end_with('…')
      expect(cut.length).to be <= 50
      expect(cut).not_to match(/wor…\z/)
    end

    it 'copes with nothing' do
      expect(described_class.first_sentence(nil)).to eq('')
    end
  end

  describe 'what the model sees' do
    it 'puts the dataset sentence, and the forms with their first sentences, into the :forms context' do
      text = described_class.context_text(:forms)
      expect(text).to start_with('DATA: ')
      expect(text).to include('FORMS (pass the name as "form"', '- member [Miembro]: People who work or study', '- funding_commitment [')
      expect(text).not_to include('userproject')
    end

    it 'gives the :dataset context without the form list' do
      text = described_class.context_text(:dataset)
      expect(text).to start_with('DATA: ')
      expect(text).not_to include('FORMS')
    end

    it 'gives the dataset sentence in both languages, whatever language the caller had set, and restores it' do
      Thread.current[:language] = 'es'
      text = described_class.context_text(:dataset)
      expect(text).to include('DATA: The administrative records', 'DATOS: Los registros administrativos')
      expect(text).to match(/empleados/)
      expect(Thread.current[:language]).to eq('es')
    end

    it 'lists the forms in English with the Spanish name in brackets' do
      text = described_class.context_text(:forms)
      expect(text).to include('- member [Miembro]: People who work or study')
      expect(text).to include('- funding_commitment [Compromiso de financiación]:')
    end

    it 'adds the data to the server instructions after the fixed rules, with the use-before-web-search cue' do
      text = described_class.instructions
      expect(text).to start_with(Mcp::INSTRUCTIONS.strip)
      expect(text).to include('BEFORE any web search')
      expect(text).to include('DATA: ', '- member [Miembro]:')
    end

    it 'shows the data in the tools that choose the form and puts the summary first' do
      %w[describe_form search_records].each do |name|
        tool = Mcp::Tool.find(name)
        description = tool.definition[:description]
        expect(description.lines.first.strip).to eq(tool.summary)
        expect(description).to include('DATA: ')
      end
      expect(Mcp::Tool.find('search_records').definition[:description]).to include('- member [Miembro]:')
      expect(Mcp::Tool.find('get_record').definition[:description]).not_to include('DATA: ')
    end
  end

  describe 'caching' do
    it 'reads the ontology once per loaded ontology' do
      described_class.context_text(:forms)
      expect(Mcp::Records::Context).not_to receive(:new)
      described_class.context_text(:forms)
    end

    it 'rebuilds after the ontology is reloaded' do
      first = described_class.context_text(:dataset)
      original = $ontology
      begin
        reloaded = RDF::Repository.new # a reload replaces the object; its id is the cache key
        original.each_statement { |statement| reloaded << statement }
        $ontology = reloaded
        expect(Mcp::Records::Context).to receive(:new).at_least(:once).and_call_original
        expect(described_class.context_text(:dataset)).to eq(first)
      ensure
        $ontology = original
      end
    end
  end

  describe 'when the ontology cannot be read' do
    it 'gives no context rather than failing the tool list' do
      allow(Mcp::Records::Context).to receive(:new).and_raise(StandardError, 'boom')
      allow(described_class).to receive(:warn)
      expect(described_class.context_text(:forms)).to be_nil
      expect(Mcp::Tool.find('search_records').definition[:description]).to start_with(Mcp::Tool.find('search_records').summary)
      expect(Mcp::Server.handle({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'tools/list' })[:result][:tools]).not_to be_empty
    end
  end
end

RSpec.describe Mcp::Tools::DescribeForm, 'with descriptions' do
  it 'returns the dataset description and each form\'s description, in the language asked for' do
    en = described_class.invoke('language' => 'en')
    es = described_class.invoke('language' => 'es')
    en_body = JSON.parse(en.first[:text])
    es_body = JSON.parse(es.first[:text])
    expect(en_body['about']).to include('administrative records')
    expect(es_body['about']).to include('registros administrativos')
    member_en = en_body['forms'].find { |f| f['form'] == 'member' }
    member_es = es_body['forms'].find { |f| f['form'] == 'member' }
    expect(member_en['description']).to match(/employees/i)
    expect(member_es['description']).to match(/empleados/i)
    expect(en_body['forms'].map { |f| f['form'] }).not_to include('userproject')
  end

  it 'includes the description on one form\'s detail too' do
    body = JSON.parse(described_class.invoke('form' => 'publication').first[:text])
    expect(body['description']).to match(/publications/i)
  end
end

RSpec.describe Mcp::Tools::SearchRecords, 'count only' do
  let(:graphs) { %w[g1 g2 g3].map { |g| "#{BASE_URI}member/context/#{g}" } }

  before do
    allow_any_instance_of(Mcp::Records::Context).to receive(:search_params).and_return({})
    allow_any_instance_of(Object).to receive(:execute_search).and_return(graphs)
  end

  it 'returns only the total for limit 0 and reads no records' do
    expect_any_instance_of(Mcp::Records::Context).not_to receive(:build_records)
    body = JSON.parse(described_class.invoke('form' => 'member', 'limit' => 0).first[:text])
    expect(body).to eq('form' => 'member', 'total' => 3, 'returned' => 0, 'records' => [])
  end

  it 'still reads records for a normal limit' do
    allow_any_instance_of(Mcp::Records::Context).to receive(:build_records).and_return([{ form: 'member', id: 'g1' }])
    body = JSON.parse(described_class.invoke('form' => 'member', 'limit' => 1).first[:text])
    expect(body).to include('total' => 3, 'returned' => 1, 'has_more' => true)
  end
end
