# frozen_string_literal: true

require_relative '../../app/controllers/application_controller'

# The email Damaris and Laura get when a member submits a record through a
# user-facing form lists whatever the member filled in - including a free-text
# comment meant for them, which is the point of that field - plus the link to
# open the record.
RSpec.describe 'the new-submission notification email' do
  let(:app_instance) { CBGP::DatabasesApp.new! }
  let(:dataset) do
    ds = CBGP::Dataset.new(type: 'userproject')
    ds.primary_id = 'sub-1'
    ds.title = 'An Application'
    comments = ds.fields.find { |f| f[:questionclass] == 'project_comments' }
    ds.public_send("#{comments[:method]}=", "Deadline is Friday.\nPlease call me.")
    ds
  end

  def body
    app_instance.send(:submission_notification_body, dataset: dataset, link: 'https://example.org/cbgp/dataset/project/sub-1')
  end

  it 'includes the submitter\'s comment, in full' do
    expect(body).to include('Comments:')
    expect(body).to include('Deadline is Friday.')
    expect(body).to include('Please call me.')
  end

  it 'still lists the other filled-in fields, the record id and the link' do
    expect(body).to include('An Application')
    expect(body).to include('Primary ID: sub-1')
    expect(body).to include('Open this record: https://example.org/cbgp/dataset/project/sub-1')
  end

  it 'leaves out fields the member left blank' do
    expect(body).not_to include('Application URL:')
  end
end
