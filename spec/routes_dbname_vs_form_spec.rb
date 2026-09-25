# frozen_string_literal: true

require 'rack/test'
require_relative '../app/controllers/application_controller'

# Regression coverage for a real bug found 2026-08-26 during beta testing:
# several routes resolved the shared storage dbname (e.g. "project", via
# get_dbname_for_form) and then wrongly passed THAT to CBGP::Dataset.new/
# new_with_defaults/new_from_raw_params's `type:` argument, instead of the
# specific form class (e.g. "national_regional_research_project").
#
# This worked by accident before Sara's project-fields ontology
# restructuring, when the dbname and the form class happened to be the same
# string ("project"). Once the shared "project" form was split into several
# specific forms sharing one dbname, `type: <dbname>` stopped resolving to
# any real ontology class at all - CBGP::Dataset.new(type: 'project') builds
# a Dataset with zero fields, and every field getter (e.g. `.title`) raises
# NoMethodError the moment a view tries to read it.
#
# Route-level (not just lib-level) coverage matters here specifically
# because the bug lived entirely in app/controllers/routes.rb - every
# lib/dataset_classes.rb spec passing was consistent with this bug existing,
# since they all correctly pass the specific form as `type:` already.
RSpec.describe 'dbname vs. specific-form-class routing', type: :request do
  include Rack::Test::Methods

  def app
    CBGP::DatabasesApp
  end

  # Every form affected by Sara's project-fields split, to make sure the fix
  # generalizes rather than only covering the one form that happened to be
  # reported.
  %w[european_research_project national_regional_research_project private_research_project personnel_project].each do |form|
    it "renders the empty add-new-record form for #{form} without a dbname/type mixup" do
      login_as_admin
      get "/cbgp/dataset/#{form}"

      expect(last_response.status).to eq(200)
      expect(last_response.body).not_to include('NoMethodError')
    end
  end

  it 'redisplays an invalid admin submission (validation-error path) without a secondary dbname/type crash' do
    # national_regional_research_project's required fields include a real
    # ORCID cross-reference (project_pi_orcid) - validate_references's
    # lookup hits a live SPARQL endpoint if not stubbed, which this suite
    # must never depend on (same reasoning as spec/lib/form_required_fields_spec.rb).
    allow(CBGP::Dataset).to receive(:get_primary_id).and_return(nil)
    login_as_admin
    # Deliberately missing every required field, to force the
    # ValidationError rescue branch (new_from_raw_params) to run.
    post '/cbgp/validate-dataset/project', 'form_class' => 'national_regional_research_project', 'primary_id' => ''

    expect(last_response.status).to eq(200)
    expect(last_response.body).not_to include('NoMethodError')
  end

  def login_as_admin
    # Rack::Protection::HostAuthorization rejects Rack::Test's default host
    # ("example.org") outright - "localhost" is Sinatra's own default
    # permitted host, so this isn't loosening anything test-specific.
    header 'Host', 'localhost'
    post '/cbgp/login', username: 'test-admin', password: 'test'
  end
end
