# frozen_string_literal: true

# Covers the generic related-records panels (lib/related_records.rb): what an
# ontology-declared local:has-related-records panel finds, lists and checks.
# The only ontology-specific part is the real declarations the first group
# reads (member/project -> funding_commitment); every rule below is exercised
# through them but lives in the panel code, not in anything commitment-aware.
RSpec.describe CBGP::RelatedRecords do
  def commitment(id:, member: '12345678Z', project: 'INT-001', percentage: '50', from: '2026-01-01', to: '')
    ds = CBGP::Dataset.new(type: 'funding_commitment')
    ds.primary_id = id
    ds.member_nie = member
    ds.project_code = project
    ds.percentage = percentage
    ds.start_date = from
    ds.end_date = to
    ds
  end

  def member_entry(dni: '12345678Z', id: 'm-1')
    ds = CBGP::Dataset.new(type: 'member')
    ds.primary_id = id
    ds.dni_nie_pas = dni
    ds
  end

  def project_entry(code: 'INT-001', id: 'p-1')
    ds = CBGP::Dataset.new(type: 'personnel_project')
    ds.primary_id = id
    ds.int_project_code = code
    ds
  end

  # Serves `records` as if the search had found them all, whatever was asked.
  def stub_related(records)
    allow(CBGP::RelatedRecords).to receive(:execute_search).and_return(records.map { |r| "graph://#{r.primary_id}" })
    # Block args are read via a helper because rspec-mocks may hand keyword
    # arguments to a stub block as a trailing positional Hash in this
    # Gemfile.lock's combo (see feedback_rspec_mocks_kwargs).
    allow(CBGP::Dataset).to receive(:load_from_graph) do |*args, **kw|
      opts = kw.empty? ? (args.last || {}) : kw
      records.find { |r| "graph://#{r.primary_id}" == opts[:graph] }
    end
    allow(CBGP::Dataset).to receive(:fetch_reference_label) do |*args, **kw|
      opts = kw.empty? ? (args.last || {}) : kw
      "Label(#{opts[:value]})"
    end
  end

  describe 'the ontology declarations' do
    def panel_names(type)
      get_related_records_panels_query(type: type).map { |r| r[:panel].to_s.split('#').last }
    end

    it 'gives Member a funding-commitments panel' do
      expect(panel_names('member')).to eq(['member_commitments_panel'])
    end

    it 'gives every Core project form the staff panel' do
      %w[european_research_project national_regional_research_project private_research_project personnel_project].each do |form|
        expect(panel_names(form)).to eq(['project_commitments_panel'])
      end
    end

    it 'resolves the shared "project" dbname to that same panel exactly once' do
      expect(panel_names('project')).to eq(['project_commitments_panel'])
    end

    it 'carries the related form\'s own label, for the "add a new ..." link' do
      row = get_related_records_panels_query(type: 'member').first
      expect(row[:related_form_label].to_s).to eq('Funding Commitment')
    end

    it 'gives the commitment form a sibling panel, keyed on its own member field' do
      expect(panel_names('funding_commitment')).to eq(['commitment_siblings_panel'])
      row = get_related_records_panels_query(type: 'funding_commitment').first
      expect(row[:key_field].to_s).to end_with('#commitment_member')
      expect(row[:related_form].to_s).to end_with('#funding_commitment')
      expect(row[:expected_total].to_s).to eq('100')
    end

    it 'has no key-field override on the member and project panels' do
      expect(get_related_records_panels_query(type: 'member').first[:key_field]).to be_nil
    end

    it 'lists the member panel columns' do
      cols = get_related_records_columns_query(panel: 'member_commitments_panel').map { |r| r[:column].to_s.split('#').last }
      expect(cols).to contain_exactly('commitment_project', 'commitment_percentage', 'commitment_start_date', 'commitment_end_date')
    end

    it 'only declares an expected total on the member side' do
      row = get_related_records_panels_query(type: 'member').first
      expect(row[:expected_total].to_s).to eq('100')
      expect(row[:tolerance].to_s).to eq('0.05')
      expect(get_related_records_panels_query(type: 'personnel_project').first[:expected_total]).to be_nil
    end
  end

  describe '.panels_for' do
    it 'returns nothing for a record that has not been saved yet' do
      entry = member_entry
      entry.primary_id = nil
      expect(described_class.panels_for(entry: entry, type: 'member')).to eq([])
    end

    it 'returns nothing for a form that declares no panel' do
      expect(described_class.panels_for(entry: project_entry, type: 'userproject')).to eq([])
    end

    context 'on a commitment itself (the other commitments of the same member)' do
      it 'matches on the open record\'s own member field, lists its siblings and warns on the total' do
        mine = commitment(id: 'c-1', member: '12345678Z', percentage: '61')
        sister = commitment(id: 'c-2', member: '12345678Z', project: 'INT-002', percentage: '30')
        stub_related([mine, sister])
        panel = described_class.panels_for(entry: mine, type: 'funding_commitment', as_of: Date.new(2026, 6, 1)).first

        expect(panel.rows.map(&:primary_id)).to contain_exactly('c-1', 'c-2')
        expect(panel.total).to eq(BigDecimal(91))
        expect(panel.warning).to be true
      end

      it 'does not warn once the siblings add up' do
        mine = commitment(id: 'c-1', percentage: '70')
        stub_related([mine, commitment(id: 'c-2', project: 'INT-002', percentage: '30')])
        panel = described_class.panels_for(entry: mine, type: 'funding_commitment', as_of: Date.new(2026, 6, 1)).first
        expect(panel.warning).to be false
      end

      it 'searches by the open record\'s member key' do
        mine = commitment(id: 'c-1', member: '99999999R')
        searched = nil
        allow(CBGP::RelatedRecords).to receive(:execute_search) do |*args, **kw|
          searched = (kw.empty? ? args.last : kw)[:search_params]
          []
        end
        described_class.panels_for(entry: mine, type: 'funding_commitment')
        expect(searched).to eq('commitment_member' => '99999999R')
      end
    end

    context 'for a member with a complete 50/30/20 split' do
      let(:records) do
        [commitment(id: 'c-1', project: 'P1', percentage: '50'),
         commitment(id: 'c-2', project: 'P2', percentage: '30'),
         commitment(id: 'c-3', project: 'P3', percentage: '20')]
      end
      let(:panel) do
        stub_related(records)
        described_class.panels_for(entry: member_entry, type: 'member', as_of: Date.new(2026, 6, 1)).first
      end

      it 'lists each commitment, resolving the project xref to its label' do
        expect(panel.rows.size).to eq(3)
        expect(panel.rows.flat_map(&:cells)).to include('Label(P1)', 'Label(P2)', 'Label(P3)')
        expect(panel.columns).to include('Percentage of salary cost')
      end

      it 'totals 100 with no warning' do
        expect(panel.total).to eq(BigDecimal(100))
        expect(panel.warning).to be false
        expect(panel.active_count).to eq(3)
      end
    end

    it 'warns (but still lists everything) when the active total is not 100' do
      stub_related([commitment(id: 'c-1', percentage: '50'), commitment(id: 'c-2', percentage: '70')])
      panel = described_class.panels_for(entry: member_entry, type: 'member', as_of: Date.new(2026, 6, 1)).first
      expect(panel.total).to eq(BigDecimal(120))
      expect(panel.warning).to be true
      expect(panel.rows.size).to eq(2)
    end

    it 'warns on a partially-entered split' do
      stub_related([commitment(id: 'c-1', percentage: '70')])
      panel = described_class.panels_for(entry: member_entry, type: 'member', as_of: Date.new(2026, 6, 1)).first
      expect(panel.warning).to be true
    end

    it 'tolerates rounding noise within the declared tolerance (3 x 33.33)' do
      stub_related(%w[c-1 c-2 c-3].map { |id| commitment(id: id, percentage: '33.33') })
      panel = described_class.panels_for(entry: member_entry, type: 'member', as_of: Date.new(2026, 6, 1)).first
      expect(panel.total).to eq(BigDecimal('99.99'))
      expect(panel.warning).to be false
    end

    it 'counts only commitments active on the as-of date, and shows ended ones as inactive' do
      stub_related([commitment(id: 'old', project: 'P1', percentage: '50', from: '2026-01-01', to: '2026-06-30'),
                    commitment(id: 'new', project: 'P1', percentage: '80', from: '2026-07-01'),
                    commitment(id: 'other', project: 'P2', percentage: '20', from: '2026-01-01')])
      before = described_class.panels_for(entry: member_entry, type: 'member', as_of: Date.new(2026, 3, 1)).first
      after = described_class.panels_for(entry: member_entry, type: 'member', as_of: Date.new(2026, 9, 1)).first

      expect([before.total, before.warning]).to eq([BigDecimal(70), true])
      expect([after.total, after.warning]).to eq([BigDecimal(100), false])
      expect(after.rows.map(&:active)).to eq([true, true, false]) # active first, ended last
      expect(after.rows.count(&:active)).to eq(2)
    end

    it 'does not warn when nothing is active at all (e.g. permanent staff with no project money)' do
      stub_related([commitment(id: 'c-1', percentage: '50', from: '2020-01-01', to: '2020-12-31')])
      panel = described_class.panels_for(entry: member_entry, type: 'member', as_of: Date.new(2026, 6, 1)).first
      expect(panel.active_count).to eq(0)
      expect(panel.warning).to be false
    end

    it 'treats a missing end date as open-ended and a future start date as not yet active' do
      stub_related([commitment(id: 'open', percentage: '100', from: '2020-01-01', to: ''),
                    commitment(id: 'future', percentage: '100', from: '2030-01-01', to: '')])
      panel = described_class.panels_for(entry: member_entry, type: 'member', as_of: Date.new(2026, 6, 1)).first
      expect(panel.total).to eq(BigDecimal(100))
    end

    it 'drops search hits that do not exactly hold this record\'s key' do
      stub_related([commitment(id: 'mine', member: '12345678Z', percentage: '100'),
                    commitment(id: 'someone-else', member: '12345678ZZ', percentage: '100'),
                    commitment(id: 'also-not', member: '9912345678Z', percentage: '100')])
      panel = described_class.panels_for(entry: member_entry, type: 'member', as_of: Date.new(2026, 6, 1)).first
      expect(panel.rows.map(&:primary_id)).to eq(['mine'])
    end

    it 'matches keys case-insensitively' do
      stub_related([commitment(id: 'c-1', member: '12345678z', percentage: '100')])
      panel = described_class.panels_for(entry: member_entry(dni: '12345678Z'), type: 'member', as_of: Date.new(2026, 6, 1)).first
      expect(panel.rows.size).to eq(1)
    end

    it 'prefills the add link with this record\'s key in the related form\'s xref field' do
      stub_related([])
      panel = described_class.panels_for(entry: member_entry(dni: '12345678Z'), type: 'member').first
      expect(panel.prefill).to eq('commitment_member' => '12345678Z')
      project = described_class.panels_for(entry: project_entry(code: 'INT-001'), type: 'project').first
      expect(project.prefill).to eq('commitment_project' => 'INT-001')
    end

    it 'shows an empty panel when the open record has no key value to match on' do
      expect(CBGP::RelatedRecords).not_to receive(:execute_search)
      panel = described_class.panels_for(entry: member_entry(dni: ''), type: 'member').first
      expect(panel.rows).to eq([])
      expect(panel.warning).to be false
    end

    it 'has a project-side panel (one internal code, no expected total, so never a warning)' do
      stub_related([commitment(id: 'c-1', project: 'INT-001', percentage: '30'), commitment(id: 'c-2', member: '87654321X', project: 'INT-001', percentage: '10')])
      allow(CBGP::RelatedRecords).to receive(:execute_search).and_return(['graph://c-1', 'graph://c-2'])
      panel = described_class.panels_for(entry: project_entry(code: 'INT-001'), type: 'project', as_of: Date.new(2026, 6, 1)).first
      expect(panel.title).to eq('Staff funded by this project')
      expect(panel.rows.size).to eq(2)
      expect(panel.expected_total).to be_nil
      expect(panel.warning).to be false
    end

    it 'fails open when the lookup blows up, rather than breaking the record page' do
      allow(CBGP::RelatedRecords).to receive(:execute_search).and_raise(StandardError, 'triple store down')
      expect { @panels = described_class.panels_for(entry: member_entry, type: 'member') }.not_to raise_error
      expect(@panels).to eq([])
    end

    it 'skips a graph that cannot be loaded instead of failing the panel' do
      stub_related([commitment(id: 'c-1', percentage: '100')])
      allow(CBGP::Dataset).to receive(:load_from_graph).and_raise(SystemExit)
      panel = described_class.panels_for(entry: member_entry, type: 'member').first
      expect(panel.rows).to eq([])
    end
  end

  describe '.summarize' do
    let(:today) { Date.new(2026, 6, 1) }
    let(:sum_field) { { method: :percentage } }
    let(:from_field) { { method: :start_date } }
    let(:to_field) { { method: :end_date } }

    def summarize(datasets, expected: '100', tolerance: nil, sum: sum_field)
      described_class.summarize(datasets: datasets, sum_field: sum, from_field: from_field, to_field: to_field,
                                expected_total: expected, tolerance: tolerance, as_of: today)
    end

    it 'returns no total and no warning without a sum field' do
      expect(summarize([], sum: nil)).to include(total: nil, warning: false, issues: [])
    end

    it 'defaults the tolerance to zero' do
      expect(summarize([commitment(id: 'c-1', project: 'P', percentage: '99.99')])[:warning]).to be true
    end

    it 'finds an over-commitment that only starts in the FUTURE, though today is fine' do
      result = summarize([commitment(id: 'a', project: 'P1', percentage: '60'),
                          commitment(id: 'b', project: 'P2', percentage: '40'),
                          commitment(id: 'c', project: 'P3', percentage: '10').tap { |c| c.start_date = '2026-10-14' }])

      expect(result[:total]).to eq(BigDecimal(100)) # today
      expect(result[:warning]).to be true
      expect(result[:issues]).to eq([{ date: Date.new(2026, 10, 14), total: BigDecimal(110) }])
    end

    it 'does not warn for a clean hand-over (old one ends the day before the new one starts)' do
      old = commitment(id: 'a', project: 'P1', percentage: '60').tap { |c| c.end_date = '2026-09-30' }
      new = commitment(id: 'b', project: 'P1', percentage: '60').tap { |c| c.start_date = '2026-10-01' }
      other = commitment(id: 'c', project: 'P2', percentage: '40')
      expect(summarize([old, new, other])).to include(warning: false, issues: [])
    end

    it 'warns on the overlap when the old record is not closed in time' do
      old = commitment(id: 'a', project: 'P1', percentage: '60').tap { |c| c.end_date = '2026-10-10' }
      new = commitment(id: 'b', project: 'P1', percentage: '60').tap { |c| c.start_date = '2026-10-01' }
      other = commitment(id: 'c', project: 'P2', percentage: '40')
      expect(summarize([old, new, other])[:issues]).to eq([{ date: Date.new(2026, 10, 1), total: BigDecimal(160) }])
    end

    it 'reports each change once, not every date that leaves the total as it was' do
      a = commitment(id: 'a', project: 'P1', percentage: '70')
      b = commitment(id: 'b', project: 'P2', percentage: '50').tap { |c| c.start_date = '2026-08-01' }
      c = commitment(id: 'c', project: 'P3', percentage: '1').tap { |x| x.start_date = '2026-09-01' }
      dates = summarize([a, b, c])[:issues].map { |i| [i[:date], i[:total]] }
      expect(dates).to eq([[today, BigDecimal(70)], [Date.new(2026, 8, 1), BigDecimal(120)], [Date.new(2026, 9, 1), BigDecimal(121)]])
    end

    it 'ignores past periods and dates when nobody is funded' do
      ended = commitment(id: 'a', project: 'P1', percentage: '50').tap { |c| c.start_date = '2020-01-01'; c.end_date = '2020-12-31' }
      expect(summarize([ended])).to include(warning: false, issues: [], active_count: 0)
    end
  end

  describe '.warning_messages' do
    it 'says "today" for now and "from <date>" for later' do
      panel = CBGP::RelatedRecords::Panel.new(
        sum_label: 'Percentage of salary cost', expected_total: BigDecimal(100), as_of: Date.new(2026, 6, 1),
        issues: [{ date: Date.new(2026, 6, 1), total: BigDecimal(70) }, { date: Date.new(2026, 10, 14), total: BigDecimal(110) }]
      )
      expect(described_class.warning_messages(panel)).to eq(
        ['Active percentage of salary cost adds up to 70.00 today, expected 100.00.',
         'Active percentage of salary cost adds up to 110.00 from 2026-10-14, expected 100.00.']
      )
    end
  end

  describe '.result_warnings (search-results banner)' do
    before { allow(CBGP::Dataset).to receive(:fetch_reference_label) { |*a, **kw| "Name(#{(kw.empty? ? a.last : kw)[:value]})" } }

    it 'checks each distinct member once, however many of their commitments are in the results' do
      a = commitment(id: 'a', member: 'M1', project: 'P1', percentage: '60')
      b = commitment(id: 'b', member: 'M1', project: 'P2', percentage: '50')
      c = commitment(id: 'c', member: 'M2', project: 'P1', percentage: '100')
      calls = []
      allow(CBGP::RelatedRecords).to receive(:related_datasets) do |*args, **kw|
        opts = kw.empty? ? args.last : kw
        calls << opts[:keys]
        { %w[M1] => [a, b], %w[M2] => [c] }[opts[:keys]]
      end

      result = described_class.result_warnings(datasets: [a, b, c], type: 'funding_commitment', as_of: Date.new(2026, 6, 1))

      expect(calls).to eq([%w[M1], %w[M2]])
      expect(result[:messages].size).to eq(1)
      expect(result[:messages].first).to include('Name(M1) (M1)', 'adds up to 110.00 today', 'expected 100.00')
    end

    it 'caps the number of members checked and reports how many were not' do
      many = (1..5).map { |i| commitment(id: "c#{i}", member: "M#{i}", project: 'P', percentage: '100') }
      allow(CBGP::RelatedRecords).to receive(:related_datasets) { |*a, **kw| many.select { |m| m.member_nie == (kw.empty? ? a.last : kw)[:keys].first } }
      result = described_class.result_warnings(datasets: many, type: 'funding_commitment', limit: 2)
      expect(result[:skipped]).to eq(3)
    end

    it 'does nothing for a form that is not the related side of a checked panel (e.g. a member search)' do
      expect(CBGP::RelatedRecords).not_to receive(:related_datasets)
      expect(described_class.result_warnings(datasets: [member_entry], type: 'member')).to eq(messages: [], skipped: 0)
    end

    it 'fails open' do
      allow(CBGP::RelatedRecords).to receive(:build_panel).and_raise(StandardError, 'boom')
      one = commitment(id: 'a', member: 'M1', project: 'P1')
      expect(described_class.result_warnings(datasets: [one], type: 'funding_commitment')).to eq(messages: [], skipped: 0)
    end
  end

  describe '.active?' do
    let(:today) { Date.new(2026, 6, 1) }

    it 'is inclusive of both bounds' do
      expect(described_class.active?(from: today, to: today, as_of: today)).to be true
    end

    it 'is false after the end and before the start' do
      expect(described_class.active?(from: nil, to: today - 1, as_of: today)).to be false
      expect(described_class.active?(from: today + 1, to: nil, as_of: today)).to be false
    end

    it 'is true when both bounds are blank' do
      expect(described_class.active?(from: nil, to: nil, as_of: today)).to be true
    end
  end
end
