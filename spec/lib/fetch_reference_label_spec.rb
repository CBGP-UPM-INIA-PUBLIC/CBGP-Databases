# frozen_string_literal: true

# Covers CBGP::Dataset.fetch_reference_label, the reverse of
# fetch_reference_suggestions: given a value already stored on a
# cross-reference field (e.g. an ORCiD saved on a Publication's
# "CBGP Author(s)" field), looks up and returns the referenced record's
# human-readable label - added 2026-08-26 because the edit form only ever
# showed the raw stored ORCiD, never the author's name.
RSpec.describe 'CBGP::Dataset.fetch_reference_label' do
  let(:member) { double('member', surname: 'Wilkinson') }

  before do
    allow(CBGP::Dataset).to receive(:resolve_key_method)
      .with('member', 'member_orcid').and_return('orcid')
    allow(CBGP::Dataset).to receive(:resolve_key_method)
      .with('member', 'member_surnames').and_return('surname')
  end

  it 'looks up the value against the via field and returns the label field' do
    allow(CBGP::Dataset).to receive(:execute_search)
      .with(hash_including(search_params: { 'member_orcid' => '0000-0001-6960-357X' }, dataset_type: 'member', broad: false))
      .and_return(['graph://member/1'])
    allow(CBGP::Dataset).to receive(:load_from_graph)
      .with(hash_including(graph: 'graph://member/1', database: 'member'))
      .and_return(member)

    label = CBGP::Dataset.fetch_reference_label(
      target_form: 'member', via_class: 'member_orcid', label_method: 'member_surnames',
      value: '0000-0001-6960-357X'
    )
    expect(label).to eq('Wilkinson')
  end

  it 'falls back to the via field itself as the label when label_method is blank' do
    allow(CBGP::Dataset).to receive(:execute_search)
      .with(hash_including(search_params: { 'member_orcid' => '0000-0001-6960-357X' }))
      .and_return(['graph://member/1'])
    orcid_only_member = double('member', orcid: '0000-0001-6960-357X')
    allow(CBGP::Dataset).to receive(:load_from_graph).and_return(orcid_only_member)

    label = CBGP::Dataset.fetch_reference_label(target_form: 'member', via_class: 'member_orcid', value: '0000-0001-6960-357X')
    expect(label).to eq('0000-0001-6960-357X')
  end

  it 'returns nil when nothing matches the value' do
    allow(CBGP::Dataset).to receive(:execute_search).and_return([])

    label = CBGP::Dataset.fetch_reference_label(
      target_form: 'member', via_class: 'member_orcid', label_method: 'member_surnames', value: 'not-a-real-orcid'
    )
    expect(label).to be_nil
  end

  it 'returns nil rather than raising when target_form, via_class, or value is blank' do
    expect(CBGP::Dataset.fetch_reference_label(target_form: '', via_class: 'member_orcid', value: 'x')).to be_nil
    expect(CBGP::Dataset.fetch_reference_label(target_form: 'member', via_class: '', value: 'x')).to be_nil
    expect(CBGP::Dataset.fetch_reference_label(target_form: 'member', via_class: 'member_orcid', value: '')).to be_nil
  end
end
