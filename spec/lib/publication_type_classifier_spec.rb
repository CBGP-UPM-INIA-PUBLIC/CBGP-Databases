# frozen_string_literal: true

# Covers publication_type classification, added 2026-08-26: DOI-registry
# "type" fields (Crossref's own vocabulary, DataCite's CSL-JSON "type") drive
# CBGP's publication_type field at import time, which was previously always
# left unset. The ontology currently only has two answers ("Article"/"Book"),
# so this is a coarse keyword bucket, not a full bibliographic taxonomy - a
# book chapter (real example: 10.1142/9789811265679_0033) lands in "Book".
RSpec.describe 'publication_type classification' do
  describe '#classify_publication_type' do
    it 'buckets journal/article-shaped types as Article' do
      expect(CBGP::Parsers.classify_publication_type('journal-article')).to eq('Article')
      expect(CBGP::Parsers.classify_publication_type('article-journal')).to eq('Article')
      expect(CBGP::Parsers.classify_publication_type('posted-content')).to eq('Article')
    end

    it 'buckets book/chapter/monograph-shaped types as Book' do
      expect(CBGP::Parsers.classify_publication_type('book-chapter')).to eq('Book')
      expect(CBGP::Parsers.classify_publication_type('chapter')).to eq('Book')
      expect(CBGP::Parsers.classify_publication_type('book')).to eq('Book')
      expect(CBGP::Parsers.classify_publication_type('monograph')).to eq('Book')
    end

    it 'defaults to Article when the type is missing or unrecognized' do
      expect(CBGP::Parsers.classify_publication_type(nil)).to eq('Article')
      expect(CBGP::Parsers.classify_publication_type('')).to eq('Article')
      expect(CBGP::Parsers.classify_publication_type('software')).to eq('Article')
    end
  end

  describe '#publication_type_answer_id' do
    let(:article_answer) { { aid: 'https://w3id.org/CBGP-App#ptype1', label: 'Article' } }
    let(:book_answer) { { aid: 'https://w3id.org/CBGP-App#ptype2', label: 'Book' } }

    before do
      allow(CBGP::Parsers).to receive(:get_answer_block_query)
        .with(hash_including(ablockid: 'publication-type'))
        .and_return([article_answer, book_answer])
    end

    it 'resolves a label to its ontology answerid fragment' do
      expect(CBGP::Parsers.publication_type_answer_id('Article')).to eq('ptype1')
      expect(CBGP::Parsers.publication_type_answer_id('Book')).to eq('ptype2')
    end

    it 'returns nil for a label with no matching answer, rather than raising' do
      expect(CBGP::Parsers.publication_type_answer_id('Chapter')).to be_nil
    end
  end
end
