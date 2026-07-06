# frozen_string_literal: true

# Test env vars — set *before* requiring configuration.rb so its Dotenv.load
# (which never overwrites already-set ENV vars) can't pull in a developer's
# real .env secrets. Keeps the suite hermetic: no network access, no real
# credentials, runs the same on any machine or in CI.
#
# CBGP_KB is the one that matters most: it points at a frozen local snapshot
# of the ontology (spec/fixtures/cbgp-application-ontology.owl) instead of
# the live https://w3id.org/CBGP-App URL, so specs never depend on network
# access or the ontology's current live state. If a spec starts failing
# because a field/widget it depends on changed shape, re-copy the fixture:
#   cp ../CBGP-Ontology/cbgp-application-ontology.owl spec/fixtures/
ENV['CBGP_USERS']     ||= '{"test-admin":{"password":"test","role":"admin"}}'
ENV['CBGP_SECRET']    ||= 'test-secret-not-for-production'
ENV['NOTIFY_TO']      ||= 'test@example.invalid'
ENV['NOTIFY_UN']      ||= 'test-user'
ENV['NOTIFY_PW']      ||= 'test-pass'
ENV['GRAPHDB_HOST']   ||= 'localhost:7200'
ENV['GRAPHDB_USER']   ||= 'test'
ENV['GRAPHDB_PASS']   ||= 'test'
ENV['GRAPHDB_DBNAME'] ||= 'test'
ENV['CBGP_KB'] ||= File.expand_path('fixtures/cbgp-application-ontology.owl', __dir__)

# Normally defined in app/controllers/application_controller.rb; redefined
# here so lib/ files can be exercised standalone without booting the full
# Sinatra app. Tests that care about a specific language set
# Thread.current[:language] directly (see spec/support if that grows).
def current_language
  Thread.current[:language] || 'en'
end

require 'json' # normally pulled in by application_controller.rb before configuration.rb
require_relative '../app/controllers/configuration'
require_relative '../lib/core'
require_relative '../lib/queries'
require_relative '../lib/dataset_classes'
require_relative '../lib/questionnaire'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.order = :random
  Kernel.srand config.seed

  # Reset to English before every example so specs aren't order-dependent on
  # whatever language a previous example happened to leave set.
  config.before do
    Thread.current[:language] = 'en'
  end
end
