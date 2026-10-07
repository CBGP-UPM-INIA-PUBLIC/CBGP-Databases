# frozen_string_literal: true

require 'rack/test'
require_relative '../../app/controllers/application_controller'

# Interface text (hints, placeholders, button captions) in the user's language.
# Found 2026-10-06: the administrator who runs most of the data entry speaks no
# English, and "Type at least 2 characters to search existing member..." was
# English whatever language was selected.
RSpec.describe 'ui_text' do
  # Every interface text is a subclass of cbgp:ui-text in the ontology; read
  # the labels straight from it, independently of the code under test.
  def ontology_labels
    query = SPARQL.parse(<<~SPARQL)
      #{PREFIXES}
      SELECT ?id ?label WHERE { ?c rdfs:subClassOf cbgp:ui-text . ?c rdfs:label ?label . BIND(STRAFTER(STR(?c), "#") AS ?id) }
    SPARQL
    query.execute($ontology).each_with_object(Hash.new { |h, k| h[k] = {} }) do |row, labels|
      labels[row[:id].to_s][row[:label].language.to_s] = row[:label].to_s
    end
  end

  let(:labels) { ontology_labels }

  def keys_used_in_code
    Dir[File.expand_path('../../app/views/*.erb', __dir__), File.expand_path('../../lib/**/*.rb', __dir__)]
      .reject { |f| f.include?('ADCAPP') }
      .flat_map { |f| File.read(f).scan(/ui_text\(\s*'([a-z_.]+)'/).flatten }.uniq
  end

  it 'finds the interface texts in the ontology' do
    expect(labels.keys).to include('ui_typeahead_hint', 'ui_typeahead_hint_field')
  end

  it 'has every text in English and Spanish' do
    labels.each { |id, by_lang| expect(by_lang.keys).to include('en', 'es'), id }
  end

  it 'uses the same %{placeholders} in both languages' do
    labels.each do |id, by_lang|
      expect(by_lang['es'].scan(/%\{(\w+)\}/).sort).to eq(by_lang['en'].scan(/%\{(\w+)\}/).sort), id
    end
  end

  it 'is safe to print inside an HTML attribute or a JavaScript template' do
    labels.each do |id, by_lang|
      by_lang.each_value do |text|
        expect(text).not_to match(/[`"<>\\]|\$\{/), "#{id}: #{text.inspect} could break out of an attribute or template literal"
      end
    end
  end

  it 'has a text in the ontology for every key the templates ask for' do
    used = keys_used_in_code
    expect(used).not_to be_empty
    expect(used.map { |k| CBGP::UIText.class_name(k) } - labels.keys).to eq([])
  end

  it 'answers in the requested language' do
    expect(ui_text('typeahead.clear', language: 'en')).to eq('clear')
    expect(ui_text('typeahead.clear', language: 'es')).to eq('borrar')
  end

  it 'follows the language the app is currently serving' do
    Thread.current[:language] = 'es'
    expect(ui_text('typeahead.clear')).to eq('borrar')
  ensure
    Thread.current[:language] = nil
  end

  it 'fills in placeholders' do
    expect(ui_text('typeahead.hint', language: 'es', target: 'miembro')).to eq(
      'Escriba al menos 2 caracteres para buscar en «miembro»...'
    )
  end

  it 'leaves an unfilled placeholder visible rather than raising' do
    expect(ui_text('typeahead.hint', language: 'en')).to include('%{target}')
  end

  it 'falls back to English for a language it does not have, and to the key for an unknown text' do
    expect(ui_text('typeahead.clear', language: 'fr')).to eq('clear')
    expect(ui_text('no.such.key', language: 'es')).to eq('no.such.key')
  end

  it 'never lets a key reach the query unchecked' do
    expect(ui_text("x} . ?s ?p ?o . {", language: 'en')).to eq("x} . ?s ?p ?o . {")
    expect(ui_text('typeahead.clear', language: "en'))")).to eq('clear')
  end

  it 'does not interpret % sequences in the values it substitutes' do
    expect(ui_text('search.enter_field_to_filter', language: 'en', field: '100%{x}')).to eq('Enter 100%{x} to filter')
  end

  it 'picks up a changed ontology text after the cache is cleared (what /cbgp/refresh does)' do
    expect(ui_text('typeahead.clear', language: 'en')).to eq('clear')
    CBGP::UIText.instance_variable_get(:@cache)[['ui_typeahead_clear', 'en']] = 'stale'
    expect(ui_text('typeahead.clear', language: 'en')).to eq('stale')
    CBGP::UIText.clear_cache!
    expect(ui_text('typeahead.clear', language: 'en')).to eq('clear')
  end
end

RSpec.describe 'the interface hints in the page', type: :request do
  include Rack::Test::Methods

  def app
    CBGP::DatabasesApp
  end

  def page_in(language, path)
    header 'Host', 'localhost'
    post '/cbgp/login', username: 'test-admin', password: 'test'
    post '/set_language', language: language
    get path
    last_response.body
  end

  it 'shows the cross-reference hint in Spanish, naming the searched record kind in Spanish too' do
    body = page_in('es', '/cbgp/dataset/funding_commitment')
    expect(body).to include('Escriba al menos 2 caracteres de')
    expect(body).not_to include('Type at least 2 characters')
    expect(body).not_to include('<small>Currently selected value') # nor the other captions of the widget
    expect(body).to include('Valor seleccionado actualmente')
    expect(body).to include("✕ borrar")
  end

  it 'shows the same hint in English when English is selected' do
    body = page_in('en', '/cbgp/dataset/funding_commitment')
    expect(body).to include('Type at least 2 characters of the')
    expect(body).to include('<small>Currently selected value:')
    expect(body).not_to include('Escriba al menos')
  end

  it 'translates the placeholders and the NOT caption of the search form' do
    es = page_in('es', '/cbgp/search-dataset/member')
    expect(es).to include('NO (excluir coincidencias)')
    expect(es).to match(/placeholder="Introduzca [^"]+ para filtrar"/)
    expect(es).not_to include('NOT (exclude matches)')
    expect(es).not_to match(/placeholder="Enter /)
    en = page_in('en', '/cbgp/search-dataset/member')
    expect(en).to include('NOT (exclude matches)')
    expect(en).to match(/placeholder="Enter [^"]+ to filter"/)
  end

  it 'leaves the record kind out of a hint when the ontology has no name for it, rather than showing a class name' do
    body = page_in('es', '/cbgp/dataset/funding_commitment')
    hints = body.scan(/const xrefHint\s*=\s*"([^"]*)"/).flatten
    expect(hints).to include('Escriba al menos 2 caracteres de «Apellido(s)» para buscar en «miembro»...')
    expect(hints.join).not_to include('«project»')
    expect(hints).to include('Escriba al menos 2 caracteres de «Título del proyecto» para buscar...')
  end

  it 'renders the Spanish hint safely in the page\'s script (as JSON, not raw)' do
    body = page_in('es', '/cbgp/dataset/funding_commitment')
    expect(body).to match(/const xrefHint\s*=\s*"Escriba al menos 2 caracteres de/)
  end
end
