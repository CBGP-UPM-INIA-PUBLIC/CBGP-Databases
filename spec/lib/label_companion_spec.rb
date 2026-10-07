# frozen_string_literal: true

# local:label-companion: a field shown with another when that one serves as a
# cross-reference label, so that two people who share a surname can be told
# apart in a lookup (found 2026-10-07: 24 surname labels in the member list
# were shared by two or three different people, and the lookup could only ever
# store one of them). The ontology says "surnames come with the name"; nothing
# in the code knows about members.
RSpec.describe 'label companions' do
  describe '.label_companions (real ontology)' do
    it 'finds the name that accompanies the surnames' do
      expect(CBGP::Dataset.label_companions('member', 'member_surnames')).to eq(['member_name'])
    end

    it 'is empty for a field with no companion, for no field, and for an unsafe name' do
      expect(CBGP::Dataset.label_companions('member', 'member_name')).to eq([])
      expect(CBGP::Dataset.label_companions('member', nil)).to eq([])
      expect(CBGP::Dataset.label_companions('member', 'x" } #')).to eq([])
    end

    it 'ignores a companion the target form does not have' do
      expect(CBGP::Dataset.label_companions('publication', 'member_surnames')).to eq([])
    end
  end

  describe 'display labels' do
    let(:person) { double('member', dni_nie_pas: '11111111A', surname: 'Alarcón Moreno', name: 'Sara', primary_id: 'u1') }

    before do
      allow(CBGP::Dataset).to receive(:resolve_key_method) do |*args|
        { 'member_dni_nie_pas' => 'dni_nie_pas', 'member_surnames' => 'surname', 'member_name' => 'name' }[args.last]
      end
      allow(CBGP::Dataset).to receive(:execute_search).and_return(['graph://g'])
      allow(CBGP::Dataset).to receive(:load_from_graph).and_return(person)
    end

    def suggest(label_method = 'member_surnames')
      CBGP::Dataset.fetch_reference_suggestions(target_form: 'member', via_class: 'member_dni_nie_pas',
                                                label_method: label_method, search_query: 'alarco')
    end

    it 'puts the companion after the label in the suggestions, surname first' do
      expect(suggest).to eq([{ value: '11111111A', label: 'Alarcón Moreno, Sara' }])
    end

    it 'still stores the key, not the shown name' do
      expect(suggest.first[:value]).to eq('11111111A')
    end

    it 'skips a companion the record has no value for, leaving no stray comma' do
      allow(CBGP::Dataset).to receive(:load_from_graph).and_return(double('m', dni_nie_pas: '2', surname: 'Alarcón Moreno', name: '', primary_id: 'u'))
      expect(suggest.first[:label]).to eq('Alarcón Moreno')
    end

    it 'shows the same label beside an already-stored value' do
      label = CBGP::Dataset.fetch_reference_label(target_form: 'member', via_class: 'member_dni_nie_pas',
                                                  label_method: 'member_surnames', value: '11111111A')
      expect(label).to eq('Alarcón Moreno, Sara')
    end

    it 'adds nothing when the label field has no companion' do
      allow(CBGP::Dataset).to receive(:label_companions).and_return([])
      expect(suggest.first[:label]).to eq('Alarcón Moreno')
    end

    it 'keeps two people who share a surname as two distinct choices' do
      allow(CBGP::Dataset).to receive(:execute_search).and_return(%w[graph://a graph://b])
      people = { 'graph://a' => double('m', dni_nie_pas: '1', surname: 'Alarcón Moreno', name: 'Pablo', primary_id: 'a'),
                 'graph://b' => double('m', dni_nie_pas: '2', surname: 'Alarcón Moreno', name: 'Sara', primary_id: 'b') }
      allow(CBGP::Dataset).to receive(:load_from_graph) { |*args, **kw| people.fetch((kw.empty? ? args.last : kw)[:graph]) }

      labels = suggest.map { |s| s[:label] }
      expect(labels).to contain_exactly('Alarcón Moreno, Pablo', 'Alarcón Moreno, Sara')
      expect(suggest.map { |s| s[:value] }).to contain_exactly('1', '2')
    end
  end
end
