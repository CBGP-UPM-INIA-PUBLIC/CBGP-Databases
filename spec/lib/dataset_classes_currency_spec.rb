# frozen_string_literal: true

# Exercises currency handling through the actual CBGP::Dataset layer (field
# lookup from the ontology fixture, coercion, and the friendly-error path),
# as opposed to spec/lib/currency_spec.rb which tests the pure parse/format
# helpers in isolation.
RSpec.describe CBGP::Dataset do
  # project_total_funding is the one field currently wired to the currency
  # widget (local:object-class Currency / local:widget-type currency in the
  # ontology fixture). If that ever gets renamed/removed/repointed to a
  # different class in the ontology, these specs should fail loudly rather
  # than silently stop testing anything real.
  let(:currency_questionclass) { 'project_total_funding' }
  let(:currency_method) { :total_funding }

  before do
    field = described_class.fields_for('project').find { |f| f[:questionclass] == currency_questionclass }
    raise "fixture ontology no longer has a '#{currency_questionclass}' field - update this spec" unless field

    unless field[:class] == 'currency'
      raise "'#{currency_questionclass}' is no longer a currency field - update this spec"
    end
  end

  describe '#coerce_value with class "currency"' do
    subject(:dataset) { described_class.new(type: 'project') }

    it 'coerces valid US-style input to the canonical decimal form' do
      expect(dataset.coerce_value('15,000.5', 'currency', 'Single')).to eq('15000.50')
    end

    it 'coerces valid Spanish-style input to the same canonical form' do
      Thread.current[:language] = 'es'
      expect(dataset.coerce_value('15.000,50', 'currency', 'Single')).to eq('15000.50')
    end

    it 'raises a friendly ArgumentError for unparseable input' do
      expect { dataset.coerce_value('fifteen thousand', 'currency', 'Single') }
        .to raise_error(ArgumentError, /doesn't look like a valid amount/)
    end

    it 'treats a blank value as blank, not an error' do
      expect(dataset.coerce_value('', 'currency', 'Single')).to eq('')
    end
  end

  describe '.load_from_params_and_write' do
    let(:base_params) { { 'database' => 'project', 'primary_id' => '' } }

    context 'with an invalid currency amount' do
      let(:params) { base_params.merge(currency_questionclass => 'fifteen thousand') }

      it 'raises ValidationError instead of a raw ArgumentError' do
        expect { described_class.load_from_params_and_write(params: params) }
          .to raise_error(described_class::ValidationError)
      end

      it 'reports the failing field by its human label, not its internal method name' do
        described_class.load_from_params_and_write(params: params)
      rescue described_class::ValidationError => e
        expect(e.errors).to contain_exactly(
          hash_including(label: 'Total funding', message: a_string_matching(/doesn't look like a valid amount/))
        )
      end

      it 'never reaches write_dataset_to_db (nothing is persisted on a validation failure)' do
        allow(described_class).to receive(:write_dataset_to_db)
        begin
          described_class.load_from_params_and_write(params: params)
        rescue described_class::ValidationError
          nil
        end
        expect(described_class).not_to have_received(:write_dataset_to_db)
      end
    end

    context 'with a valid currency amount' do
      let(:params) { base_params.merge(currency_questionclass => '15,000.50') }

      before { allow(described_class).to receive(:write_dataset_to_db) }

      it 'stores the canonical decimal form and writes exactly once' do
        dataset = described_class.load_from_params_and_write(params: params)
        expect(dataset.public_send(currency_method)).to eq('15000.50')
        expect(described_class).to have_received(:write_dataset_to_db).once
      end
    end
  end

  describe '.new_from_raw_params' do
    it 'echoes back exactly what was submitted, unvalidated, for redisplay after a ValidationError' do
      params = { 'database' => 'project', 'primary_id' => '', currency_questionclass => 'fifteen thousand' }
      dataset = described_class.new_from_raw_params(type: 'project', params: params)
      expect(dataset.public_send(currency_method)).to eq('fifteen thousand')
    end
  end
end
