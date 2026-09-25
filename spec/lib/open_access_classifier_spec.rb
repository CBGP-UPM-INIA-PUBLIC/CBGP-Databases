# frozen_string_literal: true

# Covers open_access classification, added 2026-08-26 per the user's
# explicit instruction: only Crossref/DataCite's own license data may
# determine publication_open_access; OpenAIRE must never be trusted for
# this (see lib/openaire_parser.rb - #openaire_affiliations used to
# unconditionally overwrite it from OpenAIRE's bestaccessright on every
# single publication, which is exactly what this rules out). Both
# classifiers here only ever return "Yes" or nil (leave unset) - never
# "No" - since absence of a recognized open-license signal doesn't prove a
# paper is closed.
RSpec.describe 'open_access classification' do
  describe '#classify_open_access_from_crossref' do
    it 'returns "Yes" for an open-license entry with no embargo' do
      license = [{ 'URL' => 'https://creativecommons.org/licenses/by/4.0', 'delay-in-days' => 0 }]
      expect(CBGP::Parsers.classify_open_access_from_crossref(license)).to eq('Yes')
    end

    it 'returns nil (not "No") when the license entry is embargoed' do
      license = [{ 'URL' => 'https://creativecommons.org/licenses/by/4.0', 'delay-in-days' => 365 }]
      expect(CBGP::Parsers.classify_open_access_from_crossref(license)).to be_nil
    end

    it 'returns nil for a non-open license URL (e.g. a publisher TDM-only license)' do
      license = [{ 'URL' => 'https://www.some-publisher.example/tdm-license', 'delay-in-days' => 0 }]
      expect(CBGP::Parsers.classify_open_access_from_crossref(license)).to be_nil
    end

    it 'returns nil when there is no license array at all' do
      expect(CBGP::Parsers.classify_open_access_from_crossref(nil)).to be_nil
      expect(CBGP::Parsers.classify_open_access_from_crossref([])).to be_nil
    end
  end

  describe '#classify_open_access_from_datacite' do
    it 'returns "Yes" for a Creative Commons copyright string' do
      expect(CBGP::Parsers.classify_open_access_from_datacite('Creative Commons Attribution 4.0 International')).to eq('Yes')
    end

    it 'returns nil for a non-open or missing copyright string' do
      expect(CBGP::Parsers.classify_open_access_from_datacite('All rights reserved')).to be_nil
      expect(CBGP::Parsers.classify_open_access_from_datacite(nil)).to be_nil
    end
  end

  describe '#open_access_answer_id' do
    before do
      allow(CBGP::Parsers).to receive(:get_answer_block_query)
        .with(hash_including(ablockid: 'open_access'))
        .and_return([{ aid: 'https://w3id.org/CBGP-App#oa_yes', label: 'Yes' },
                     { aid: 'https://w3id.org/CBGP-App#oa_no', label: 'No' }])
    end

    it 'resolves "Yes" to its ontology answerid fragment' do
      expect(CBGP::Parsers.open_access_answer_id('Yes')).to eq('oa_yes')
    end

    it 'returns nil without querying the ontology when the label is blank' do
      expect(CBGP::Parsers).not_to receive(:get_answer_block_query)
      expect(CBGP::Parsers.open_access_answer_id(nil)).to be_nil
    end
  end
end
