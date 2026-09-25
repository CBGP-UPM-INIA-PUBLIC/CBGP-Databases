# frozen_string_literal: true

# Covers match_authors_to_personnel: the new step that decides which authors
# of a loaded publication are existing CBGP `member` records, so their ORCID
# can be recorded on publication_cbgp_authors (see the ontology change adding
# that field alongside this).
#
# Matching is exact-token (an ORCID match, or a given-first-token +
# surname-any-token match after stripping accents) - never fuzzy string
# similarity. This is deliberately looser than a full-string match: see
# lib/personnel_matcher.rb's doc comment for the 2026-08-26 stress test that
# found full-string matching missed 88% of real CBGP staff once their name
# was truncated the way DOI-registry metadata routinely truncates it (double
# surnames, compound given names). The looser rule is judged safe here
# because this matcher only ever runs against a publication's author list,
# which is already known to include at least one real CBGP co-author - the
# risk being guarded against is under-matching, not a random collision.
# Journal/DOI-registry metadata is far more likely to drop diacritics than
# the canonical personnel record is, so both sides are unaccented before
# comparison rather than trusting the incoming spelling.
RSpec.describe 'CBGP::Parsers.match_authors_to_personnel' do
  # load_member_index batches all members into one fetch_datasets_raw_data
  # call (see lib/personnel_matcher.rb - avoids the N+1 of one
  # CBGP::Dataset.load_from_graph per member, which mattered a lot once
  # match_authors_to_personnel started running once per publication in a
  # bulk DOI load).
  let(:garcia_member) { { member_name: 'María', member_surnames: 'García', member_orcid: '0000-0001-2345-6789' } }
  let(:no_orcid_member) { { member_name: 'Juan', member_surnames: 'Pérez', member_orcid: '' } }
  # A realistic Spanish double-surname + compound-given-name CBGP member, to
  # cover the looser matching rule's actual purpose.
  let(:double_surname_member) { { member_name: 'Ana María', member_surnames: 'López García', member_orcid: '0000-0003-1111-2222' } }

  before do
    allow(CBGP::Parsers).to receive(:execute_search)
      .with(hash_including(dataset_type: 'member', broad: true))
      .and_return(%w[graph://member/1 graph://member/2 graph://member/3])
    allow(CBGP::Parsers).to receive(:fetch_datasets_raw_data)
      .with(hash_including(graph_uris: %w[graph://member/1 graph://member/2 graph://member/3], database: 'member'))
      .and_return([garcia_member, no_orcid_member, double_surname_member])
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

  it 'matches a truncated second surname against a double-surname member (the looser rule)' do
    authors = [{ name: 'Ana García', given: 'Ana', family: 'García', orcid: '' }]

    expect(CBGP::Parsers.match_authors_to_personnel(authors: authors)).to eq(['0000-0003-1111-2222'])
  end

  it 'matches a compound given name via its first token only' do
    authors = [{ name: 'Ana López García', given: 'Ana María', family: 'López', orcid: '' }]

    expect(CBGP::Parsers.match_authors_to_personnel(authors: authors)).to eq(['0000-0003-1111-2222'])
  end

  it 'still requires the given name to agree, even with the looser surname rule' do
    authors = [{ name: 'Pedro García', given: 'Pedro', family: 'García', orcid: '' }]

    expect(CBGP::Parsers.match_authors_to_personnel(authors: authors)).to eq([])
  end

  it 'returns an empty array for an empty author list without querying members' do
    expect(CBGP::Parsers).not_to receive(:execute_search)
    expect(CBGP::Parsers.match_authors_to_personnel(authors: [])).to eq([])
  end
end
