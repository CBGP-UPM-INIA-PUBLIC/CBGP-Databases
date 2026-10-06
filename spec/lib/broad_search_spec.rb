# frozen_string_literal: true

# "Show all records", the `today` date keyword and "<field>__orempty" - the
# generic search features behind questions like "what is running now" (a date
# range that has started and not ended, where no end date counts as not
# ended) and "list everything". None of this knows any record type: the field
# names below are only examples to build queries against.
RSpec.describe 'broad search features' do
  let(:today) { Date.new(2026, 10, 6) }

  def query_for(params)
    build_search_query(search_params: params, dataset_type: 'personnel_project')
  end

  describe '__all (Show all records)' do
    it 'is recognised only for the exact value 1' do
      expect(show_all_requested?('__all' => '1')).to be(true)
      expect(show_all_requested?('__all' => '0')).to be(false)
      expect(show_all_requested?('project_title' => 'x')).to be(false)
      expect(show_all_requested?({})).to be(false)
    end

    it 'lists every record, ignoring any criteria typed alongside' do
      expect(self).to receive(:search_for_all_graphs).with(hash_including(dataset_type: 'personnel_project')).and_return(%w[g1 g2])
      expect(DATABASE).not_to receive(:query)

      expect(execute_search(dataset_type: 'personnel_project',
                            search_params: { '__all' => '1', 'project_title' => 'nothing like this' })).to eq(%w[g1 g2])
    end

    it 'is not a search term: on its own it builds no query' do
      expect(query_for('__all' => '1')).to be_nil
    end

    it 'does NOT make a lookup with an empty value return everything' do
      # get_primary_id, the DOI check and related-records all search on one
      # key; a blank key must still mean "no match", never "every record".
      expect(self).not_to receive(:search_for_all_graphs)
      expect(DATABASE).not_to receive(:query)

      expect(execute_search(dataset_type: 'personnel_project', search_params: { 'project_title' => '' })).to eq([])
    end
  end

  describe 'the "today" date keyword' do
    before { allow(Date).to receive(:today).and_return(today) }

    it 'stands for the current date in either bound, in any case' do
      query = query_for('project_start_date' => { 'end' => 'today' }, 'project_end_date' => { 'start' => 'TODAY' })

      expect(query).to include('?datevalue_0 <= xsd:date("2026-10-06")')
      expect(query).to include('?datevalue_1 >= xsd:date("2026-10-06")')
    end

    it 'still rejects anything else that is not a date' do
      expect { query_for('project_start_date' => { 'end' => 'tomorrow' }) }.to raise_error(ArgumentError, /Invalid date/)
    end
  end

  describe '"<field>__orempty" (matches, or has no value)' do
    let(:running) do
      { 'project_start_date' => { 'end' => '2026-10-06' },
        'project_end_date' => { 'start' => '2026-10-06' }, 'project_end_date__orempty' => '1' }
    end

    it 'makes the value optional and lets an unbound one through the filter' do
      query = query_for(running)

      expect(query).to include('FILTER (!BOUND(?datevalue_1) || (?datevalue_1 >= xsd:date("2026-10-06")))')
      expect(query).to match(/OPTIONAL \{[^}]*\?attribute_1 rdf:type cbgp:project_end_date \.\s*\}/)
    end

    it 'keeps the FILTER outside the OPTIONAL group (inside it would only restrict the optional part)' do
      optional_blocks = query_for(running).scan(/OPTIONAL \{(.*?)\n\s*\}\n/m).flatten
      expect(optional_blocks).not_to be_empty
      expect(optional_blocks.join).not_to include('FILTER')
    end

    it 'leaves the other fields as ordinary required conditions' do
      query = query_for(running)

      expect(query).to include('FILTER (?datevalue_0 <= xsd:date("2026-10-06"))')
      expect(query.scan('OPTIONAL').size).to eq(1)
    end

    it 'works for a text field too' do
      query = query_for('project_title' => 'robot', 'project_title__orempty' => '1')

      expect(query).to match(/FILTER \(!BOUND\(\?value_0\) \|\| \(regex\(STR\(\?value_0\), "[^"]*", "i"\)\)\)/)
    end

    it 'is not itself a search field' do
      expect(query_for('project_title__orempty' => '1')).to be_nil
    end

    it 'does nothing without the flag' do
      expect(query_for('project_end_date' => { 'start' => '2026-10-06' })).not_to include('OPTIONAL')
    end

    it 'yields to NOT when both are set (they would contradict each other)' do
      query = query_for('project_title' => 'robot', 'project_title__orempty' => '1', 'project_title__not' => '1')

      expect(query).to include('FILTER NOT EXISTS')
      expect(query).not_to include('OPTIONAL')
    end
  end
end
