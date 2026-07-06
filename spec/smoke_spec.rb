# frozen_string_literal: true

RSpec.describe 'spec_helper smoke test' do
  it 'loads the app libs offline against the fixture ontology' do
    expect(defined?(CBGP::Dataset)).to be_truthy
    expect($ontology.size).to be > 0 # rubocop:disable Style/GlobalVars -- $ontology is the app's existing global, not new here
  end
end
