# frozen_string_literal: true

# validate_local_name!, validate_date!, and validate_iri_component!
# (lib/queries.rb) close a class of SPARQL-injection gap that
# escape_for_literal never covered: values interpolated as bare SPARQL
# syntax (a class/questionclass local name after "cbgp:", a raw xsd:date
# literal, an IRI inside <...>) rather than inside a quoted string literal.
# Harmless while every one of these values came from a fixed HTML dropdown;
# not harmless once the same call paths (lib/queries.rb, lib/history_queries.rb)
# take arguments supplied directly by an LLM/agent via the planned MCP query
# servers. See spec/lib/search_accent_spec.rb and escape_for_literal_spec.rb
# for the sibling literal-context escaping this complements.
RSpec.describe 'SPARQL identifier/date/IRI validation' do
  describe '#validate_local_name!' do
    it 'accepts a real ontology local name unchanged' do
      expect(validate_local_name!('member_orcid', field: 'questionclass')).to eq('member_orcid')
    end

    it 'accepts underscores, dashes, and digits after the first character' do
      expect(validate_local_name!('project-type_2', field: 'form')).to eq('project-type_2')
    end

    it 'rejects a value that would break out of "cbgp:#{value}" into new query syntax' do
      expect do
        validate_local_name!('member . } DROP GRAPH <urn:x> #', field: 'form')
      end.to raise_error(ArgumentError, /Invalid form/)
    end

    it 'rejects a value starting with a digit' do
      expect { validate_local_name!('123abc', field: 'form') }.to raise_error(ArgumentError)
    end

    it 'rejects blank input' do
      expect { validate_local_name!('', field: 'form') }.to raise_error(ArgumentError)
      expect { validate_local_name!(nil, field: 'form') }.to raise_error(ArgumentError)
    end
  end

  describe '#validate_date!' do
    it 'normalizes a real date to YYYY-MM-DD' do
      expect(validate_date!('2026-01-05')).to eq('2026-01-05')
    end

    it 'requires zero-padded YYYY-MM-DD, rejecting other real-date spellings Date.parse would otherwise accept' do
      # Deliberately stricter than Date.parse: anchoring to one exact format
      # is what makes the injection-rejection below possible in the first
      # place (Date.parse alone would just extract the date and ignore the
      # rest of the string).
      expect { validate_date!('2026-1-5') }.to raise_error(ArgumentError)
    end

    it 'rejects a value that would break out of the "..."^^xsd:date literal into new FILTER syntax' do
      expect do
        validate_date!('2020-01-01"^^xsd:date) } UNION { FILTER(true')
      end.to raise_error(ArgumentError, /Invalid date/)
    end

    it 'rejects nonsense that is not a date at all' do
      expect { validate_date!('not-a-date') }.to raise_error(ArgumentError)
    end
  end

  describe '#validate_iri_component!' do
    it 'accepts an ORCID, which starts with a digit and would fail validate_local_name!' do
      expect(validate_iri_component!('0000-0001-2345-6789', field: 'primary_id')).to eq('0000-0001-2345-6789')
    end

    it 'accepts a DOI, which contains slashes and dots' do
      expect(validate_iri_component!('10.1038/sdata.2016.18', field: 'primary_id')).to eq('10.1038/sdata.2016.18')
    end

    it 'rejects a value containing ">" that would close the <...> IRIREF early' do
      expect do
        validate_iri_component!('abc><urn:evil> a <urn:injected', field: 'primary_id')
      end.to raise_error(ArgumentError, /Invalid primary_id/)
    end

    it 'rejects a value containing a raw double quote or backslash' do
      expect { validate_iri_component!('abc"def', field: 'primary_id') }.to raise_error(ArgumentError)
      expect { validate_iri_component!('abc\\def', field: 'primary_id') }.to raise_error(ArgumentError)
    end

    it 'rejects whitespace/control characters' do
      expect { validate_iri_component!("abc\ndef", field: 'primary_id') }.to raise_error(ArgumentError)
    end
  end

  describe '#build_search_query date-range handling' do
    it 'still builds a valid date-range filter for real dates (unchanged behavior)' do
      query = build_search_query(
        search_params: { 'member_start_date' => { 'start' => '2020-01-01', 'end' => '2020-12-31' } },
        dataset_type: 'member'
      )

      expect(query).to include('FILTER (?datevalue >= "2020-01-01"^^xsd:date && ?datevalue <= "2020-12-31"^^xsd:date)')
    end

    it 'raises rather than interpolate an injected start_date into the generated query' do
      expect do
        build_search_query(
          search_params: { 'member_start_date' => { 'start' => '2020-01-01"^^xsd:date) } #', 'end' => '' } },
          dataset_type: 'member'
        )
      end.to raise_error(ArgumentError)
    end

    it 'raises on an invalid dataset_type instead of interpolating it unchecked' do
      expect do
        build_search_query(search_params: { 'member_name' => 'maria' }, dataset_type: 'member } DROP ALL #')
      end.to raise_error(ArgumentError, /Invalid dataset_type/)
    end
  end
end
