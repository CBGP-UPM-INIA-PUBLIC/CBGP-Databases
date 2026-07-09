# frozen_string_literal: true

# Covers the Stage 2 "time machine" query layer added 2026-07-09
# (lib/history_queries.rb) — see .claude/plans/squishy-bouncing-unicorn.md
# for the full design and spec/lib/history_capture_spec.rb for the Stage 1
# recording mechanism this builds on.
#
# Two real bugs were found and fixed via live manual verification before
# these specs existed (see the "Output wrapping" comment block at the top of
# lib/history_queries.rb) — several tests below exist specifically to catch
# a regression of those: the RDF::Graph value-collision bug (record_history_result
# and temporal_search_result specs) and the frozen/shared-prefixes-hash bug
# (#time_machine_prefixes specs).
RSpec.describe 'Time machine query layer' do
  # Builds triples matching the real SIO reified-attribute pattern
  # (attribute node `rdf:type cbgp:<questionclass>` + `sio:SIO_000300
  # <value>`) that snapshot_field_values expects — one attribute node per
  # value, exactly like a real Multiple-cardinality field.
  def field_triples(questionclass:, values:)
    Array(values).flat_map do |value|
      attr = RDF::URI("urn:test:attr/#{questionclass}/#{SecureRandom.uuid}")
      [
        RDF::Statement.new(attr, RDF.type, RDF::URI("#{CBGP_NS}#{questionclass}")),
        RDF::Statement.new(attr, RDF::URI(SIO_VALUE_PREDICATE), RDF::Literal(value.to_s))
      ]
    end
  end

  def result_node(repo)
    repo.query([nil, RDF.type, RDF::URI("#{LOCAL_NS}TimeMachineResult")]).first.subject
  end

  ##############################################################################
  # Pure helpers
  ##############################################################################

  describe '#snapshot_field_values' do
    it 'extracts a Single-cardinality field value' do
      triples = field_triples(questionclass: 'project_title', values: ['My Project'])
      expect(snapshot_field_values(triples: triples, questionclass: 'project_title')).to eq(['My Project'])
    end

    it 'extracts every value of a Multiple-cardinality field' do
      triples = field_triples(questionclass: 'project_pi_orcid', values: %w[0000-0001 0000-0002])
      expect(snapshot_field_values(triples: triples, questionclass: 'project_pi_orcid'))
        .to contain_exactly('0000-0001', '0000-0002')
    end

    it 'returns an empty array when the field is absent from these triples' do
      triples = field_triples(questionclass: 'project_title', values: ['My Project'])
      expect(snapshot_field_values(triples: triples, questionclass: 'project_total_funding')).to eq([])
    end

    it 'does not confuse two different fields that happen to share a value' do
      triples = field_triples(questionclass: 'project_title', values: ['Active']) +
                field_triples(questionclass: 'member_status', values: ['Active'])
      expect(snapshot_field_values(triples: triples, questionclass: 'member_status')).to eq(['Active'])
    end
  end

  describe '#date_in_range?' do
    let(:snapshot) { { triples: field_triples(questionclass: 'project_start_date', values: ['2025-03-15']) } }

    it 'matches a date inside an inclusive range' do
      expect(date_in_range?(snapshot, date_field: 'project_start_date', start_date: '2025-01-01',
                                      end_date: '2025-06-30')).to be true
    end

    it 'excludes a date outside the range' do
      expect(date_in_range?(snapshot, date_field: 'project_start_date', start_date: '2025-04-01',
                                      end_date: '2025-06-30')).to be false
    end

    it 'matches range boundaries inclusively' do
      expect(date_in_range?(snapshot, date_field: 'project_start_date', start_date: '2025-03-15',
                                      end_date: '2025-03-15')).to be true
    end

    it 'treats a blank start as an open lower bound' do
      expect(date_in_range?(snapshot, date_field: 'project_start_date', start_date: '',
                                      end_date: '2025-06-30')).to be true
    end

    it 'treats a blank end as an open upper bound' do
      expect(date_in_range?(snapshot, date_field: 'project_start_date', start_date: '2025-01-01',
                                      end_date: nil)).to be true
    end

    it 'matches everything when both bounds are blank' do
      expect(date_in_range?(snapshot, date_field: 'project_start_date', start_date: nil, end_date: nil)).to be true
    end

    it 'excludes a snapshot missing the date field entirely' do
      empty_snapshot = { triples: [] }
      expect(date_in_range?(empty_snapshot, date_field: 'project_start_date', start_date: '2025-01-01',
                                            end_date: '2025-06-30')).to be false
    end

    it 'does not raise on an unparseable date value, just excludes it' do
      bad_snapshot = { triples: field_triples(questionclass: 'project_start_date', values: ['not-a-date']) }
      expect(date_in_range?(bad_snapshot, date_field: 'project_start_date', start_date: '2025-01-01',
                                          end_date: '2025-06-30')).to be false
    end
  end

  describe '#sum_numeric_field' do
    it 'sums a numeric field across several snapshots' do
      snapshots = [
        { triples: field_triples(questionclass: 'project_total_funding', values: ['10000.00']) },
        { triples: field_triples(questionclass: 'project_total_funding', values: ['25000.50']) }
      ]
      expect(sum_numeric_field(snapshots: snapshots, questionclass: 'project_total_funding'))
        .to eq(BigDecimal('35000.50'))
    end

    it 'returns zero for an empty snapshot set' do
      expect(sum_numeric_field(snapshots: [], questionclass: 'project_total_funding')).to eq(BigDecimal(0))
    end

    it 'treats a snapshot missing the field as contributing zero' do
      snapshots = [{ triples: field_triples(questionclass: 'project_title', values: ['x']) }]
      expect(sum_numeric_field(snapshots: snapshots, questionclass: 'project_total_funding')).to eq(BigDecimal(0))
    end

    it 'does not raise on a non-numeric value, just skips it' do
      snapshots = [{ triples: field_triples(questionclass: 'project_total_funding', values: ['not-a-number']) }]
      expect(sum_numeric_field(snapshots: snapshots, questionclass: 'project_total_funding')).to eq(BigDecimal(0))
    end
  end

  describe '#primary_id_from_history_graph' do
    it 'extracts the primary_id segment between /history/ and the trailing uuid' do
      graph = "#{BASE_URI}project/history/abc-123/def-456-uuid"
      expect(primary_id_from_history_graph(graph_uri: graph, form_type: 'project')).to eq('abc-123')
    end
  end

  describe '#insert_into_named_graph' do
    it 'stamps every inserted statement with the given graph_name' do
      repo = RDF::Repository.new
      triples = field_triples(questionclass: 'project_title', values: ['x'])
      graph_name = RDF::URI('http://example.org/g1')

      insert_into_named_graph(repository: repo, triples: triples, graph_name: graph_name)

      expect(repo.each_statement.to_a).to all(have_attributes(graph_name: graph_name))
      expect(repo.count).to eq(triples.size)
    end
  end

  describe '#time_machine_prefixes' do
    it 'returns a copy equal in content to the shared constant' do
      expect(time_machine_prefixes).to eq(TIME_MACHINE_PREFIXES)
    end

    it 'returns an unfrozen object, unlike the constant itself' do
      expect(time_machine_prefixes).not_to be_frozen
      expect(TIME_MACHINE_PREFIXES).to be_frozen
    end

    it 'never hands back the same object as the constant' do
      expect(time_machine_prefixes).not_to equal(TIME_MACHINE_PREFIXES)
    end

    it 'mutating the returned copy never affects the shared constant (the JSON-LD writer mutates prefixes: in place)' do
      copy = time_machine_prefixes
      copy[:cbgp] = 'mutated'
      expect(TIME_MACHINE_PREFIXES[:cbgp]).to eq('https://w3id.org/CBGP-App#')
    end
  end

  ##############################################################################
  # Low-level readers (SPARQL mocked, same style as history_capture_spec.rb)
  ##############################################################################

  describe '#current_graph_uris' do
    it 'returns every graph URI bound in the result' do
      allow(DATABASE).to receive(:query)
        .with(a_string_matching(/SELECT DISTINCT \?g WHERE \{ GRAPH \?g \{ \?s a cbgp:member \} \}/))
        .and_return([RDF::Query::Solution.new(g: RDF::URI('http://example.org/g1')),
                     RDF::Query::Solution.new(g: RDF::URI('http://example.org/g2'))])

      expect(current_graph_uris(form_type: 'member')).to contain_exactly('http://example.org/g1', 'http://example.org/g2')
    end
  end

  describe '#history_snapshots' do
    it 'scopes to one primary_id via a STRSTARTS filter when given' do
      prefix_filter = %r{FILTER\(STRSTARTS\(STR\(\?g\), "#{Regexp.escape(BASE_URI)}member/history/abc-123/"\)\)}
      allow(HISTORY_DATABASE).to receive(:query).with(a_string_matching(prefix_filter)).and_return([])

      history_snapshots(form_type: 'member', primary_id: 'abc-123')
      expect(HISTORY_DATABASE).to have_received(:query)
    end

    it 'parses generated/invalidated/reason/detail out of each bound row' do
      solution = RDF::Query::Solution.new(
        g: RDF::URI("#{BASE_URI}member/history/abc-123/v1"),
        generated: RDF::Literal.new('2024-01-01T00:00:00Z', datatype: RDF::XSD.dateTime),
        invalidated: RDF::Literal.new('2024-06-01T00:00:00Z', datatype: RDF::XSD.dateTime),
        reason: RDF::Literal('superseded'),
        detail: RDF::Literal('Status: A -> B')
      )
      allow(HISTORY_DATABASE).to receive(:query).and_return([solution])

      result = history_snapshots(form_type: 'member', primary_id: 'abc-123')
      expect(result).to eq([{
                             graph_uri: "#{BASE_URI}member/history/abc-123/v1",
                             generated_at: '2024-01-01T00:00:00Z',
                             invalidated_at: '2024-06-01T00:00:00Z',
                             reason: 'superseded',
                             detail: 'Status: A -> B'
                           }])
    end

    it 'leaves invalidated_at/reason/detail nil when their triples are absent' do
      solution = RDF::Query::Solution.new(
        g: RDF::URI("#{BASE_URI}member/history/abc-123/v1"),
        generated: RDF::Literal.new('2024-01-01T00:00:00Z', datatype: RDF::XSD.dateTime)
      )
      allow(HISTORY_DATABASE).to receive(:query).and_return([solution])

      result = history_snapshots(form_type: 'member', primary_id: 'abc-123').first
      expect(result[:invalidated_at]).to be_nil
      expect(result[:reason]).to be_nil
      expect(result[:detail]).to be_nil
    end
  end

  describe '#find_primary_id' do
    it 'returns the primary_id from the current repository when found there' do
      allow(DATABASE).to receive(:query)
        .with(a_string_matching(/rdf:type cbgp:member_orcid/))
        .and_return([RDF::Query::Solution.new(id: RDF::Literal('abc-123'))])

      expect(find_primary_id(form_type: 'member', questionclass: 'member_orcid', value: '0000-0001')).to eq('abc-123')
    end

    it 'falls back to scanning history when not found in the current repository' do
      allow(DATABASE).to receive(:query).and_return([])
      allow(HISTORY_DATABASE).to receive(:query)
        .with(a_string_matching(/FILTER\(STRSTARTS/))
        .and_return([RDF::Query::Solution.new(id: RDF::Literal('old-456'))])

      expect(find_primary_id(form_type: 'member', questionclass: 'member_orcid', value: '0000-0002')).to eq('old-456')
    end

    it 'returns nil when not found anywhere' do
      allow(DATABASE).to receive(:query).and_return([])
      allow(HISTORY_DATABASE).to receive(:query).and_return([])

      expect(find_primary_id(form_type: 'member', questionclass: 'member_orcid', value: 'nonexistent')).to be_nil
    end

    it 'escapes a quote and a backslash in the search value via escape_for_literal (see escape_for_literal_spec.rb)' do
      allow(DATABASE).to receive(:query).and_return([])
      allow(HISTORY_DATABASE).to receive(:query).and_return([])

      find_primary_id(form_type: 'member', questionclass: 'member_orcid', value: 'a"b\\c')
      expect(DATABASE).to have_received(:query).with(a_string_matching(/sio:SIO_000300 "a\\"b\\\\c"/))
    end
  end

  ##############################################################################
  # Composed functions (intermediate calls stubbed via allow(self), same
  # pattern history_capture_spec.rb already uses for delete_dataset_query)
  ##############################################################################

  describe '#full_timeline' do
    let(:history_v1) do
      { graph_uri: "#{BASE_URI}member/history/abc/v1", generated_at: '2024-01-01T00:00:00Z',
        invalidated_at: '2024-06-01T00:00:00Z', reason: 'superseded', detail: 'Status: A -> B' }
    end
    let(:history_v1_triples) { field_triples(questionclass: 'member_status', values: ['A']) }
    let(:current_graph) { "#{BASE_URI}member/context/abc" }
    let(:current_triples) { field_triples(questionclass: 'member_status', values: ['B']) }

    # NOTE: .with(hash_including(...)) rather than a literal keyword hash —
    # this rspec-mocks/Ruby version combo fails to match an exact keyword
    # hash against real keyword-argument calls even when they print
    # identically (confirmed via a minimal repro outside this suite);
    # hash_including matches correctly and is used throughout this file for
    # every keyword-argument stub.
    before do
      allow(self).to receive(:history_snapshots)
        .with(hash_including(form_type: 'member', primary_id: 'abc')).and_return([history_v1])
      allow(self).to receive(:read_graph_triples)
        .with(hash_including(graph_uri: history_v1[:graph_uri], repository: HISTORY_DATABASE))
        .and_return(history_v1_triples)
    end

    context 'when a current version still exists' do
      before do
        allow(self).to receive(:read_graph_triples)
          .with(hash_including(graph_uri: current_graph, repository: DATABASE)).and_return(current_triples)
        allow(self).to receive(:read_current_meta)
          .with(hash_including(graph_uri: current_graph))
          .and_return(created: '2024-01-01T00:00:00Z', modified: '2024-06-01T00:05:00Z')
      end

      it 'appends the current version last, with invalidated_at/reason/detail nil' do
        timeline = full_timeline(form_type: 'member', primary_id: 'abc')
        expect(timeline.last).to include(graph_uri: current_graph, invalidated_at: nil, reason: nil, detail: nil)
      end

      it 'orders versions chronologically by generated_at' do
        timeline = full_timeline(form_type: 'member', primary_id: 'abc')
        expect(timeline.map { |v| v[:graph_uri] }).to eq([history_v1[:graph_uri], current_graph])
      end

      it 'keeps each version\'s field value distinguishable' do
        timeline = full_timeline(form_type: 'member', primary_id: 'abc')
        expect(snapshot_field_values(triples: timeline[0][:triples], questionclass: 'member_status')).to eq(['A'])
        expect(snapshot_field_values(triples: timeline[1][:triples], questionclass: 'member_status')).to eq(['B'])
      end
    end

    context 'when the record has since been deleted (no current graph)' do
      before do
        allow(self).to receive(:read_graph_triples)
          .with(hash_including(graph_uri: current_graph, repository: DATABASE)).and_return([])
      end

      it 'returns only the history snapshots, nothing synthesized for a nonexistent current version' do
        timeline = full_timeline(form_type: 'member', primary_id: 'abc')
        expect(timeline.size).to eq(1)
        expect(timeline.first[:graph_uri]).to eq(history_v1[:graph_uri])
      end
    end
  end

  describe '#latest_known_snapshots' do
    it 'uses the current graph for a record that still exists' do
      live_graph = "#{BASE_URI}project/context/live-1"
      allow(self).to receive(:current_graph_uris).with(hash_including(form_type: 'project')).and_return([live_graph])
      allow(self).to receive(:history_snapshots).with(hash_including(form_type: 'project')).and_return([])
      allow(self).to receive(:read_graph_triples)
        .with(hash_including(graph_uri: live_graph, repository: DATABASE))
        .and_return(field_triples(questionclass: 'project_title', values: ['Live Project']))

      result = latest_known_snapshots(form_type: 'project')
      expect(result.size).to eq(1)
      expect(result.first).to include(primary_id: 'live-1', is_current: true)
    end

    it 'falls back to the latest history snapshot for a deleted record (durability through deletion)' do
      older = { graph_uri: "#{BASE_URI}project/history/deleted-1/v1", invalidated_at: '2024-01-01T00:00:00Z' }
      newer = { graph_uri: "#{BASE_URI}project/history/deleted-1/v2", invalidated_at: '2024-06-01T00:00:00Z' }
      allow(self).to receive(:current_graph_uris).with(hash_including(form_type: 'project')).and_return([])
      allow(self).to receive(:history_snapshots).with(hash_including(form_type: 'project')).and_return([older, newer])
      allow(self).to receive(:read_graph_triples)
        .with(hash_including(graph_uri: newer[:graph_uri], repository: HISTORY_DATABASE))
        .and_return(field_triples(questionclass: 'project_title', values: ['Deleted Project']))

      result = latest_known_snapshots(form_type: 'project')
      expect(result.size).to eq(1)
      expect(result.first).to include(primary_id: 'deleted-1', graph_uri: newer[:graph_uri], is_current: false)
    end

    it 'prefers the current graph over any leftover history snapshots for the same record' do
      live_graph = "#{BASE_URI}project/context/p1"
      hist = { graph_uri: "#{BASE_URI}project/history/p1/v1", invalidated_at: '2024-01-01T00:00:00Z' }
      allow(self).to receive(:current_graph_uris).with(hash_including(form_type: 'project')).and_return([live_graph])
      allow(self).to receive(:history_snapshots).with(hash_including(form_type: 'project')).and_return([hist])
      allow(self).to receive(:read_graph_triples)
        .with(hash_including(graph_uri: live_graph, repository: DATABASE))
        .and_return(field_triples(questionclass: 'project_title', values: ['Current']))

      result = latest_known_snapshots(form_type: 'project')
      expect(result.size).to eq(1)
      expect(result.first).to include(primary_id: 'p1', is_current: true)
    end
  end

  describe '#filter_snapshots_during' do
    let(:matching) do
      { primary_id: 'p1', graph_uri: 'g1',
        triples: field_triples(questionclass: 'project_type', values: ['Articulo-60']) +
          field_triples(questionclass: 'project_start_date', values: ['2025-03-01']) }
    end
    let(:wrong_type) do
      { primary_id: 'p2', graph_uri: 'g2',
        triples: field_triples(questionclass: 'project_type', values: ['Articulo-83']) +
          field_triples(questionclass: 'project_start_date', values: ['2025-03-01']) }
    end
    let(:wrong_date) do
      { primary_id: 'p3', graph_uri: 'g3',
        triples: field_triples(questionclass: 'project_type', values: ['Articulo-60']) +
          field_triples(questionclass: 'project_start_date', values: ['2024-01-01']) }
    end

    before do
      allow(self).to receive(:latest_known_snapshots)
        .with(hash_including(form_type: 'project')).and_return([matching, wrong_type, wrong_date])
    end

    it 'keeps only snapshots matching every facet and date range' do
      result = filter_snapshots_during(
        form_type: 'project',
        facets: { 'project_type' => 'Articulo-60' },
        date_ranges: { 'project_start_date' => { start: '2025-01-01', end: '2025-06-30' } }
      )
      expect(result.map { |s| s[:primary_id] }).to eq(['p1'])
    end

    it 'returns everything when no facets or date ranges are given' do
      expect(filter_snapshots_during(form_type: 'project').size).to eq(3)
    end

    it 'ANDs multiple facets together, not ORs them' do
      result = filter_snapshots_during(
        form_type: 'project',
        facets: { 'project_type' => 'Articulo-60', 'project_start_date' => '2024-01-01' }
      )
      expect(result.map { |s| s[:primary_id] }).to eq(['p3'])
    end
  end

  describe '#record_history_result' do
    it 'returns nil when the identifier resolves to nothing' do
      allow(self).to receive(:find_primary_id).and_return(nil)
      expect(record_history_result(form_type: 'member', questionclass: 'member_orcid', value: 'nope')).to be_nil
    end

    context 'with a real two-version timeline' do
      let(:v1_uri) { "#{BASE_URI}member/history/abc/v1" }
      let(:v2_uri) { "#{BASE_URI}member/context/abc" }

      before do
        allow(self).to receive(:find_primary_id).and_return('abc')
        allow(self).to receive(:full_timeline)
          .with(hash_including(form_type: 'member', primary_id: 'abc')).and_return(
            [
              { graph_uri: v1_uri, triples: field_triples(questionclass: 'member_status', values: ['Inactive']),
                generated_at: '2024-01-01T00:00:00Z', invalidated_at: '2024-06-01T00:00:00Z',
                reason: 'superseded', detail: 'Status: Active -> Inactive' },
              { graph_uri: v2_uri, triples: field_triples(questionclass: 'member_status', values: ['Active']),
                generated_at: '2024-06-01T00:00:00Z', invalidated_at: nil, reason: nil, detail: nil }
            ]
          )
      end

      it 'keeps each version\'s field distinguishable (regression: used to collide in a flat RDF::Graph)' do
        repo = record_history_result(form_type: 'member', questionclass: 'member_orcid', value: '0000-0001')

        v1_triples = repo.query([nil, nil, nil, RDF::URI(v1_uri)]).to_a
        v2_triples = repo.query([nil, nil, nil, RDF::URI(v2_uri)]).to_a

        expect(snapshot_field_values(triples: v1_triples, questionclass: 'member_status')).to eq(['Inactive'])
        expect(snapshot_field_values(triples: v2_triples, questionclass: 'member_status')).to eq(['Active'])
      end

      it 'links the result node to every version via local:version' do
        repo = record_history_result(form_type: 'member', questionclass: 'member_orcid', value: '0000-0001')
        version_links = repo.query([result_node(repo), RDF::URI("#{LOCAL_NS}version"), nil]).map(&:object)
        expect(version_links).to contain_exactly(RDF::URI(v1_uri), RDF::URI(v2_uri))
      end

      it 'carries prov:invalidatedAtTime/local:history-reason only on the superseded version' do
        repo = record_history_result(form_type: 'member', questionclass: 'member_orcid', value: '0000-0001')
        expect(repo.query([RDF::URI(v1_uri), RDF::URI("#{LOCAL_NS}history-reason"), nil]).first.object.to_s)
          .to eq('superseded')
        expect(repo.query([RDF::URI(v2_uri), RDF::URI("#{LOCAL_NS}history-reason"), nil]).to_a).to be_empty
      end

      it 'records the queried identifier and queryType on the result node' do
        repo = record_history_result(form_type: 'member', questionclass: 'member_orcid', value: '0000-0001')
        node = result_node(repo)
        expect(repo.query([node, RDF::URI("#{LOCAL_NS}queryType"), nil]).first.object.to_s).to eq('record-history')
        expect(repo.query([node, RDF::URI("#{CBGP_NS}member_orcid"), nil]).first.object.to_s).to eq('0000-0001')
      end
    end
  end

  describe '#temporal_search_result' do
    let(:snap1) do
      { primary_id: 'p1', graph_uri: 'g1',
        triples: field_triples(questionclass: 'project_total_funding', values: ['10000.00']) }
    end
    let(:snap2) do
      { primary_id: 'p2', graph_uri: 'g2',
        triples: field_triples(questionclass: 'project_total_funding', values: ['25000.00']) }
    end

    before do
      allow(self).to receive(:filter_snapshots_during).and_return([snap1, snap2])
    end

    it 'defaults to queryType temporal-search and omits totalAmount/summedField when sum_field is not given' do
      repo = temporal_search_result(form_type: 'project', facets: { 'project_type' => 'Articulo-60' })
      node = result_node(repo)
      expect(repo.query([node, RDF::URI("#{LOCAL_NS}queryType"), nil]).first.object.to_s).to eq('temporal-search')
      expect(repo.query([node, RDF::URI("#{LOCAL_NS}totalAmount"), nil]).to_a).to be_empty
      expect(repo.query([node, RDF::URI("#{LOCAL_NS}summedField"), nil]).to_a).to be_empty
    end

    it 'switches to queryType temporal-aggregate and computes the correct total when sum_field is given' do
      repo = temporal_search_result(form_type: 'project', sum_field: 'project_total_funding')
      node = result_node(repo)
      expect(repo.query([node, RDF::URI("#{LOCAL_NS}queryType"), nil]).first.object.to_s).to eq('temporal-aggregate')
      expect(repo.query([node, RDF::URI("#{LOCAL_NS}totalAmount"),
                         nil]).first.object.object).to eq(BigDecimal('35000.00'))
      expect(repo.query([node, RDF::URI("#{LOCAL_NS}summedField"),
                         nil]).first.object.to_s).to eq('project_total_funding')
    end

    it 'records the correct recordCount regardless of whether sum_field is given' do
      repo = temporal_search_result(form_type: 'project')
      node = result_node(repo)
      expect(repo.query([node, RDF::URI("#{LOCAL_NS}recordCount"), nil]).first.object.object).to eq(2)
    end

    it 'links every matching snapshot as a contributingRecord, each kept in its own named graph' do
      repo = temporal_search_result(form_type: 'project')
      node = result_node(repo)
      links = repo.query([node, RDF::URI("#{LOCAL_NS}contributingRecord"), nil]).map { |s| s.object.to_s }
      expect(links).to contain_exactly('g1', 'g2')

      g1_triples = repo.query([nil, nil, nil, RDF::URI('g1')]).to_a
      expect(snapshot_field_values(triples: g1_triples, questionclass: 'project_total_funding')).to eq(['10000.00'])
    end

    it 'records the facets and date range that were queried' do
      repo = temporal_search_result(
        form_type: 'project',
        facets: { 'project_type' => 'Articulo-60' },
        date_ranges: { 'project_start_date' => { start: '2025-01-01', end: '2025-06-30' } }
      )
      node = result_node(repo)
      expect(repo.query([node, RDF::URI("#{CBGP_NS}project_type"), nil]).first.object.to_s).to eq('Articulo-60')
      expect(repo.query([node, RDF::URI("#{LOCAL_NS}queriedIntervalStart"), nil]).first.object.to_s).to eq('2025-01-01')
      expect(repo.query([node, RDF::URI("#{LOCAL_NS}queriedIntervalEnd"), nil]).first.object.to_s).to eq('2025-06-30')
    end
  end
end
