# frozen_string_literal: true

# The files a deployment starts from: .env.example (the template the docs tell
# people to copy) and .dockerignore (what keeps secrets and the local database
# out of the Docker image that gets pushed to a registry). Both were missing
# once, which meant "cp .env.example .env" failed and a build would have baked
# the real .env and the whole local database into the image.
RSpec.describe 'deployment files' do
  let(:root) { File.expand_path('..', __dir__) }

  def env_example_keys
    File.readlines(File.join(root, '.env.example')).filter_map { |l| l[/\A#?([A-Z][A-Z0-9_]+)=/, 1] }
  end

  # Every environment variable the application and its utilities read.
  def keys_read_by_code
    files = Dir[File.join(root, '{app/controllers,lib,utilities}/**/*.rb')] + [File.join(root, 'run.rb')]
    files.flat_map { |f| File.read(f).scan(/ENV(?:\.fetch\(|\[)\s*['"]([A-Z][A-Z0-9_]+)['"]/).flatten }.uniq
  end

  it 'has a .env.example' do
    expect(File.exist?(File.join(root, '.env.example'))).to be(true)
  end

  it 'lists every setting the code reads (so the template cannot drift)' do
    ignored = %w[RACK_ENV] # set by the web server, not by the deployer
    missing = keys_read_by_code - ignored - env_example_keys
    expect(missing).to eq([]), "not in .env.example: #{missing.join(', ')}"
  end

  it 'contains only placeholders, never what looks like a real secret' do
    text = File.read(File.join(root, '.env.example'))
    expect(text).to include('change-me')
    expect(text).not_to match(/PASS=(?!change-me|\s*$)\S/)
  end

  it 'is not hidden from git by .gitignore' do
    expect(File.read(File.join(root, '.gitignore'))).to match(/^!\.env\.example$/)
  end

  describe '.dockerignore' do
    let(:lines) { File.readlines(File.join(root, '.dockerignore')).map(&:strip).reject { |l| l.empty? || l.start_with?('#') } }

    it 'keeps the real .env, the local database and git history out of the image' do
      expect(lines).to include('.env', '.env.*', 'virtuoso-data', '.git')
    end

    it 'does not exclude anything the application needs to run' do
      %w[app lib run.rb entrypoint.sh Gemfile Gemfile.lock VERSION].each do |needed|
        expect(lines).not_to include(needed)
      end
    end
  end
end
