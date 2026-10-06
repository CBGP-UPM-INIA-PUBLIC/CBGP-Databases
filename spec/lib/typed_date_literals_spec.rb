# frozen_string_literal: true

# Dates are stored as real xsd:date literals, typed at ingestion from the
# field's declared class (ontology `local:class date`), not as plain strings.
#
# Why: SPARQL compares a plain/xsd:string literal with an xsd:date
# SILENTLY WRONGLY on Virtuoso (no error, wrong rows - e.g. "start <= today"
# returned nothing). Every date-range search was affected, on every form.
# Typing the value when it is written is the only fix that does not need a
# cast in every query, and it keeps the stored data honest.
RSpec.describe 'typed date literals at write time' do
  describe '#sparql_literal' do
    it 'types a date-class value as xsd:date' do
      expect(sparql_literal('2026-01-31', 'date')).to eq('"2026-01-31"^^xsd:date')
    end

    it 'is case-insensitive about the class name' do
      expect(sparql_literal('2026-01-31', 'Date')).to eq('"2026-01-31"^^xsd:date')
    end

    it 'leaves every other class as a plain, escaped string' do
      expect(sparql_literal('say "hi"', 'string')).to eq('"say \\"hi\\""')
      expect(sparql_literal('2026-01-31', 'string')).to eq('"2026-01-31"')
      expect(sparql_literal('15000.5', 'currency')).to eq('"15000.5"')
      expect(sparql_literal('x', nil)).to eq('"x"')
    end

    it 'refuses a date-class value that is not a real calendar date, rather than storing a string' do
      expect { sparql_literal('2026-02-30', 'date') }.to raise_error(ArgumentError, /Invalid date/)
      expect { sparql_literal('next week', 'date') }.to raise_error(ArgumentError, /Invalid date/)
      expect { sparql_literal('2026-01-01"^^xsd:date . } #', 'date') }.to raise_error(ArgumentError)
    end
  end

  describe '#write_dataset_to_db_query' do
    let(:dataset) do
      ds = CBGP::Dataset.new(type: 'personnel_project')
      ds.primary_id = 'abc-123'
      ds.title = 'A Project'
      ds
    end

    it 'writes the date field as xsd:date and the title as a plain string' do
      date_field = dataset.fields.find { |f| f[:class] == 'date' }
      skip 'no date field on this form' unless date_field
      dataset.public_send("#{date_field[:method]}=", '2026-01-01')

      query = write_dataset_to_db_query(dataset: dataset, oldid: nil, form: 'personnel_project')[:query]

      expect(query).to include('"2026-01-01"^^xsd:date')
      expect(query).to include('sio:SIO_000300 "A Project" .')
    end
  end

  describe 'field classes' do
    # A form whose ontology declares one date-picker field as a *string*
    # (several real ones were), and one that is declared correctly.
    def stub_fake_form(widget_uri:, declared_class:)
      allow_any_instance_of(Object).to receive(:get_questionnaire_sections_query)
        .and_return([{ sec: 'https://w3id.org/CBGP-App#sec', label: 'Sec' }])
      allow_any_instance_of(Object).to receive(:get_section_questions_query).and_return([
        { q: 'https://w3id.org/CBGP-App#thing_date', label: 'A date', widget: widget_uri,
          class: declared_class, method: 'thing_date', cardinality: 'Single', sequence: 1 }
      ])
    end

    after { CBGP::Dataset.clear_caches! }

    it 'treats a date-widget field as class date even when the ontology declares it a string' do
      CBGP::Dataset.clear_caches!
      stub_fake_form(widget_uri: 'https://w3id.org/CBGP-App#date', declared_class: 'String')
      expect(CBGP::Dataset.fields_for('fake_form_a').first[:class]).to eq('date')
    end

    it 'leaves a non-date widget alone' do
      CBGP::Dataset.clear_caches!
      stub_fake_form(widget_uri: 'https://w3id.org/CBGP-App#text', declared_class: 'String')
      expect(CBGP::Dataset.fields_for('fake_form_b').first[:class]).to eq('string')
    end

    it 'coerces such a field as a date (normalizing it to YYYY-MM-DD) and rejects junk' do
      CBGP::Dataset.clear_caches!
      stub_fake_form(widget_uri: 'https://w3id.org/CBGP-App#date', declared_class: 'String')
      ds = CBGP::Dataset.new(type: 'fake_form_c')
      ds.thing_date = '1 March 2020'
      expect(ds.thing_date).to eq('2020-03-01')
      expect { ds.thing_date = 'not a date' }.to raise_error(ArgumentError)
    end
  end
end
