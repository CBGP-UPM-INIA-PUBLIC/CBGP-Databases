# frozen_string_literal: true

# fetch_reference_suggestions / fetch_reference_label when the key (or label)
# field of the referenced record is itself repeatable - a project can have
# several internal codes, so its getter returns an Array. The suggestion's
# value used to be `Array#to_s`, i.e. the literal text ["UI-PROJ-1"], which
# then got stored as the cross-reference and posted back as a search term
# (and, with the quote-escaping bug, crashed the search). Found 2026-10-05
# in the browser.
RSpec.describe 'cross-reference suggestions from repeatable key fields' do
  let(:project) { double('project', int_project_code: ['UI-PROJ-1', 'ALT-2'], title: 'My project', primary_id: 'uuid-1') }
  let(:single_key_member) { double('member', dni_nie_pas: '12345678Z', surname: 'García', primary_id: 'uuid-2') }

  before do
    allow(CBGP::Dataset).to receive(:resolve_key_method) do |*args|
      { 'project_internal_code' => 'int_project_code', 'project_title' => 'title',
        'member_dni_nie_pas' => 'dni_nie_pas', 'member_surnames' => 'surname' }[args.last]
    end
    allow(CBGP::Dataset).to receive(:execute_search).and_return(['graph://g'])
  end

  def suggest(target, via, label)
    CBGP::Dataset.fetch_reference_suggestions(target_form: target, via_class: via, label_method: label, search_query: 'x')
  end

  it 'offers one suggestion per key value, each a plain string' do
    allow(CBGP::Dataset).to receive(:load_from_graph).and_return(project)
    result = suggest('project', 'project_internal_code', 'project_title')
    expect(result).to eq([{ value: 'UI-PROJ-1', label: 'My project' }, { value: 'ALT-2', label: 'My project' }])
    expect(result.map { |r| r[:value] }).to all(satisfy { |v| !v.include?('[') && !v.include?('"') })
  end

  it 'is unchanged for an ordinary single-valued key' do
    allow(CBGP::Dataset).to receive(:load_from_graph).and_return(single_key_member)
    expect(suggest('member', 'member_dni_nie_pas', 'member_surnames')).to eq([{ value: '12345678Z', label: 'García' }])
  end

  it 'skips records with no key value at all' do
    allow(CBGP::Dataset).to receive(:load_from_graph).and_return(double('p', int_project_code: [], title: 'T', primary_id: 'u'))
    expect(suggest('project', 'project_internal_code', 'project_title')).to eq([])
  end

  it 'joins a repeatable label field' do
    allow(CBGP::Dataset).to receive(:load_from_graph).and_return(double('p', int_project_code: ['A-1'], title: %w[One Two], primary_id: 'u'))
    expect(suggest('project', 'project_internal_code', 'project_title')).to eq([{ value: 'A-1', label: 'One, Two' }])
  end

  it 'fetch_reference_label returns a readable label even when the label field is repeatable' do
    allow(CBGP::Dataset).to receive(:load_from_graph).and_return(double('p', int_project_code: ['A-1'], title: %w[One Two], primary_id: 'u'))
    label = CBGP::Dataset.fetch_reference_label(target_form: 'project', via_class: 'project_internal_code',
                                                label_method: 'project_title', value: 'A-1')
    expect(label).to eq('One, Two')
  end
end
