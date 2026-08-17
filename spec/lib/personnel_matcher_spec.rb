# frozen_string_literal: true

# Covers match_authors_to_personnel: the new step that decides which authors
# of a loaded publication are existing CBGP `member` records, so their ORCID
# can be recorded on publication_cbgp_authors (see the ontology change adding
# that field alongside this).
#
# Matching is deliberately exact-or-nothing (an ORCID match, or a full
# given+family name match after stripping accents) - never fuzzy - because a
# false positive here would misattribute an outside co-author's identity to a
# CBGP member. Journal/DOI-registry metadata is far more likely to drop
# diacritics than the canonical personnel record is, so both sides are
# unaccented before comparison rather than trusting the incoming spelling.
RSpec.describe 'CBGP::Parsers.match_authors_to_personnel' do
  let(:garcia_member) { double('member', name: 'María', surname: 'García', orcid: '0000-0001-2345-6789') }
  let(:no_orcid_member) { double('member', name: 'Juan', surname: 'Pérez', orcid: '') }

  before do
    allow(CBGP::Parsers).to receive(:execute_search)
      .with(hash_including(dataset_type: 'member', broad: true))
      .and_return(%w[graph://member/1 graph://member/2])
    allow(CBGP::Dataset).to receive(:load_from_graph)
      .with(hash_including(graph: 'graph://member/1', database: 'member'))
      .and_return(garcia_member)
    allow(CBGP::Dataset).to receive(:load_from_graph)
      .with(hash_including(graph: 'graph://member/2', database: 'member'))
      .and_return(no_orcid_member)
  end

  it 'matches by exact ORCID when the source metadata provides one' do
    authors = [{ name: 'M García', given: 'M', family: 'García', orcid: '0000-0001-2345-6789' }]

    expect(CBGP::Parsers.match_authors_to_personnel(authors: authors)).to eq(['0000-0001-2345-6789'])
  end

  it 'falls back to an exact accent-insensitive given+family match when there is no ORCID' do
    authors = [{ name: 'Maria Garcia', given: 'Maria', family: 'Garcia', orcid: '' }]

    expect(CBGP::Parsers.match_authors_to_personnel(authors: authors)).to eq(['0000-0001-2345-6789'])
  end

  it 'does not match on surname alone (avoids a false positive across two different people)' do
    authors = [{ name: 'Pedro García', given: 'Pedro', family: 'García', orcid: '' }]

    expect(CBGP::Parsers.match_authors_to_personnel(authors: authors)).to eq([])
  end

  it 'skips an outside co-author with no ORCID and no matching member name' do
    authors = [{ name: 'Jane Outsider', given: 'Jane', family: 'Outsider', orcid: '' }]

    expect(CBGP::Parsers.match_authors_to_personnel(authors: authors)).to eq([])
  end

  it 'skips a name match against a member who has no ORCID on file' do
    authors = [{ name: 'Juan Pérez', given: 'Juan', family: 'Perez', orcid: '' }]

    expect(CBGP::Parsers.match_authors_to_personnel(authors: authors)).to eq([])
  end

  it 'deduplicates when the same member is matched more than once' do
    authors = [
      { name: 'M García', given: 'M', family: 'García', orcid: '0000-0001-2345-6789' },
      { name: 'Maria Garcia', given: 'Maria', family: 'Garcia', orcid: '' }
    ]

    expect(CBGP::Parsers.match_authors_to_personnel(authors: authors)).to eq(['0000-0001-2345-6789'])
  end

  it 'returns an empty array for an empty author list without querying members' do
    expect(CBGP::Parsers).not_to receive(:execute_search)
    expect(CBGP::Parsers.match_authors_to_personnel(authors: [])).to eq([])
  end
end
