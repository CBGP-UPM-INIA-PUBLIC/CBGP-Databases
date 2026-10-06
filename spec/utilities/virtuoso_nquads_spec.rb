# frozen_string_literal: true

require 'open3'
require 'tmpdir'

# utilities/virtuoso_nquads.sh exports a Virtuoso store as N-Quads and loads
# such files back. Its real work needs a running Virtuoso container (it was
# verified against real stores: export, import into a new store, identical
# checksum over every statement), so this spec only covers what can be checked
# anywhere, without Docker: the script is valid, refuses a wrong call, fails
# loudly (and without side effects) when it cannot reach the store, and ships
# the dump procedure it installs.
RSpec.describe 'utilities/virtuoso_nquads.sh' do
  let(:script) { File.expand_path('../../utilities/virtuoso_nquads.sh', __dir__) }
  let(:sql) { File.expand_path('../../utilities/virtuoso_dump_nquads.sql', __dir__) }

  def run(*args)
    out, err, status = Open3.capture3(script, *args)
    [out, err, status.exitstatus]
  end

  it 'is a valid, executable bash script' do
    expect(File.executable?(script)).to be(true)
    _out, err, status = Open3.capture3('bash', '-n', script)
    expect(status.success?).to be(true), err
  end

  it 'shows its usage, and exits 2, when called with the wrong arguments' do
    _out, err, code = run
    expect(code).to eq(2)
    expect(err).to include('virtuoso_nquads.sh export', 'virtuoso_nquads.sh import')
  end

  it 'rejects an unknown mode' do
    _out, err, code = run('frobnicate', 'a-container', 'pw', '/tmp')
    expect(code).not_to eq(0)
    expect(err).not_to be_empty
  end

  it 'fails with a clear message, exit 1, when it cannot reach the container' do
    _out, err, code = run('export', 'no-such-container-for-this-spec', 'pw', Dir.mktmpdir)
    expect(code).to eq(1)
    expect(err).to match(/cannot reach container 'no-such-container-for-this-spec'/)
  end

  it 'ships the dump procedure it installs, credited to its source' do
    text = File.read(sql)
    expect(text).to match(/CREATE PROCEDURE dump_nquads/)
    expect(text).to include('http_nquad')
    expect(text).to include('https://vos.openlinksw.com/owiki/wiki/VOS/VirtRDFDumpNQuad')
  end
end
