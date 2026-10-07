# frozen_string_literal: true

# Numbers in the triple store are canonical ("60.00", "15000.50"), whatever language the
# viewer is using. Loading a record, and storing a calculated result, went through the same
# setter that parses what a person TYPES - in the viewer's number format. In a Spanish
# session "60.00" is not a valid typed amount (the Spanish form is "60,00"), so any page or
# search result holding a number or currency value failed with
#   Invalid value 60.00 for type number: '60.00' doesn't look like a valid amount
# (found on the demo server, 2026-10-07, searching funding commitments in Spanish).
RSpec.describe 'stored numbers are canonical in every UI language' do
  before { Thread.current[:language] = 'es' }
  after  { Thread.current[:language] = 'en' }

  let(:graph) { 'http://example.org/graphs/commitment/context/c-1' }

  it 'loads a stored number from a graph in a Spanish session' do
    ds = CBGP::Dataset.load_from_graph(graph: graph, database: 'funding_commitment',
                                       pre_fetched_details: { commitment_percentage: '60.00' }, pre_fetched_primary_id: 'c-1')
    expect(ds.percentage).to eq('60.00')
  end

  it 'loads a stored currency amount with a decimal point in a Spanish session' do
    ds = CBGP::Dataset.load_from_graph(graph: graph, database: 'personnel_project',
                                       pre_fetched_details: { personnel_project_total_funding: '1234.56' }, pre_fetched_primary_id: 'p-1')
    expect(ds.total_funding).to eq('1234.56')
  end

  it 'loads by primary id in a Spanish session too (the edit page)' do
    allow(CBGP::Dataset).to receive(:retrieve_dataset_graph_query).and_return([{ g: graph }])
    allow(CBGP::Dataset).to receive(:fetch_datasets_raw_data)
      .and_return([{ dataset: graph, commitment_percentage: '60.00' }])
    ds = CBGP::Dataset.load_from_primary_id(primary_id: 'c-1', database: 'funding_commitment')
    expect(ds.percentage).to eq('60.00')
  end

  it 'leaves the viewer\'s language as it found it, even if loading fails' do
    expect do
      CBGP::Dataset.load_from_graph(graph: graph, database: 'funding_commitment',
                                    pre_fetched_details: { commitment_percentage: 'not a number' }, pre_fetched_primary_id: 'c-1')
    end.to raise_error(ArgumentError)
    expect(Thread.current[:language]).to eq('es')
  end

  it 'stores a calculated currency result in a Spanish session' do
    ds = CBGP::Dataset.new(type: 'personnel_project')
    field = ds.fields.find { |f| f[:questionclass] == 'personnel_project_total_funding' }
    expect(CBGP::Dataset.send(:compute_and_store_formula_field, ds, field, '15000.50 * 0.13', {})).to be_nil
    expect(ds.total_funding).to eq('1950.07')
  end

  it 'still reads what a person types in the Spanish format' do
    ds = CBGP::Dataset.new(type: 'funding_commitment')
    ds.percentage = '60,50'
    expect(ds.percentage).to eq('60.50')
    expect { ds.percentage = '60.50' }.to raise_error(ArgumentError) # a typed English-style amount is still refused
  end
end
