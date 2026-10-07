# frozen_string_literal: true

# A single-valued field that receives a LIST must never be stored as the text of
# that list. This happened for real: a page was opened while a field was still
# repeatable (it posts "name[]"), the ontology then made the field Single, and the
# stale page was saved - the record kept the literal text ["UI-PROJ-1"] instead of
# UI-PROJ-1, and everything that looked the record up by that value found nothing.
RSpec.describe 'CBGP::Dataset#coerce_value on a single-valued field given a list' do
  let(:ds) { CBGP::Dataset.new(type: 'member') }

  it 'unwraps a list holding one value' do
    expect(ds.coerce_value(['UI-PROJ-1'], 'string', 'Single')).to eq('UI-PROJ-1')
    expect(ds.coerce_value([' UI-PROJ-1 ', ''], 'string', 'Single')).to eq('UI-PROJ-1')
  end

  it 'unwraps it for every value type, not just text' do
    expect(ds.coerce_value(['2026-03-04'], 'date', 'Single')).to eq('2026-03-04')
    expect(ds.coerce_value(['7'], 'integer', 'Single')).to eq(7)
  end

  it 'treats a list of blanks as empty' do
    expect(ds.coerce_value(['', ' '], 'string', 'Single')).to eq('')
    expect(ds.coerce_value([], 'string', 'Single')).to eq('')
  end

  it 'refuses several values rather than keeping one silently or joining them' do
    expect { ds.coerce_value(%w[A-1 B-2], 'string', 'Single') }
      .to raise_error(ArgumentError, /only one value/)
  end

  it 'leaves repeatable fields exactly as before' do
    expect(ds.coerce_value(['A-1', '', 'B-2'], 'string', 'Multiple')).to eq(%w[A-1 B-2])
  end

  it 'leaves plain single values exactly as before' do
    expect(ds.coerce_value(' x ', 'string', 'Single')).to eq('x')
  end
end
