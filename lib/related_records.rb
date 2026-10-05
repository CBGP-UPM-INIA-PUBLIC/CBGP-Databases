# frozen_string_literal: true

require 'bigdecimal'
require 'date'

# Generic "related records" panels: the ontology can declare, via
# local:has-related-records, that when a record of some form is open, the
# records of ANOTHER form that point back at it should be listed beneath it
# (e.g. a member's funding commitments, a project's funded staff) - and,
# optionally, that a numeric field of the currently-active ones should add
# up to an expected total, with a warning when it does not.
#
# Nothing here knows about members, projects or commitments. Everything -
# which forms, which cross-reference field links them, which columns, which
# field is summed, which fields bound "active", the expected total, the
# tolerance - comes from the ontology (see get_related_records_panels_query
# in lib/queries.rb and the related-records-definition class comment in the
# ontology for the vocabulary).
#
# How a related record is matched back to the open record: the related
# form's +related-via+ field is an ordinary cross-reference
# (local:references / local:references-via). Its stored value is the value
# the OPEN record holds in the referenced key field (e.g. the member's
# DNI/NIE/PAS), so the open record's value of that key field is looked up
# in the related form's +related-via+ field.
#
# The warning is computed fresh on every read and never stored, so it can
# never go stale, and a record set that is mid-entry (e.g. 70% allocated so
# far) simply shows the warning until it is complete. It is advisory only;
# nothing is ever blocked.
module CBGP
  module RelatedRecords
    Panel = Struct.new(
      :title, :related_form, :related_form_label, :columns, :rows, :total, :sum_label, :expected_total, :tolerance,
      :active_count, :warning, :issues, :as_of, :subject, :add_path, :prefill, :fields, keyword_init: true
    )
    # +values+ (optional) is, per column, the [stored value, shown text] pairs
    # behind +cells+, and the panel's +fields+ the matching field descriptors:
    # what lets the view turn each value into a search link (search_link_html)
    # rather than only printing the joined text.
    Row = Struct.new(:primary_id, :cells, :active, :sort_date, :values, keyword_init: true)

    # @param entry [CBGP::Dataset] the open record; unsaved ones (no
    #   primary_id) have nothing pointing at them yet
    # @param type [String] the open record's form class, or its dbname if
    #   that is all the caller has (resolved to every form sharing it)
    # @param as_of [Date] the day "active" is judged against
    # @return [Array<Panel>] one per panel the form declares; [] if none
    #   (or if the ontology's declaration is unusable - failing open, so a
    #   mistake in a panel definition can never stop a record opening)
    def self.panels_for(entry:, type:, as_of: Date.today)
      return [] if entry.nil? || entry.primary_id.to_s.strip.empty?

      get_related_records_panels_query(type: type).filter_map do |declaration|
        build_panel(entry: entry, declaration: declaration, as_of: as_of)
      rescue StandardError => e
        warn "[RELATED-RECORDS] panel #{declaration[:panel]} skipped: #{e.class}: #{e.message}"
        nil
      end
    rescue StandardError => e
      warn "[RELATED-RECORDS] panels for #{type.inspect} unavailable: #{e.class}: #{e.message}"
      []
    end

    def self.build_panel(entry:, declaration:, as_of:)
      related_form = fragment(declaration[:related_form])
      via_class = fragment(declaration[:via])
      related_fields = CBGP::Dataset.fields_for(related_form)

      via_field = related_fields.find { |f| f[:questionclass] == via_class }
      return nil unless via_field && via_field[:references_via]

      # The key the related records hold: this entry's value of the field
      # the related form's xref stores (e.g. member_dni_nie_pas) - or, when the
      # panel declares local:related-key-field, of that field instead. That is
      # for a panel on the related form itself ("the other commitments of the
      # same member"): the open record holds the key directly in its own
      # xref field (commitment_member), not in the referenced form's field.
      key_class = declaration[:key_field] ? fragment(declaration[:key_field]) : fragment(via_field[:references_via])
      key_field = entry.fields.find { |f| f[:questionclass] == key_class }
      return nil unless key_field

      keys = values_of(entry, key_field)
      datasets = related_datasets(related_form: related_form, via_field: via_field, keys: keys)

      columns = columns_for(declaration: declaration, related_fields: related_fields)
      from_field = field_named(related_fields, declaration[:from_field])
      to_field = field_named(related_fields, declaration[:to_field])
      sum_field = field_named(related_fields, declaration[:sum_field])

      rows = datasets.map do |ds|
        Row.new(
          primary_id: ds.primary_id,
          cells: columns.map { |f| display_value(ds, f) },
          values: columns.map { |f| values_of(ds, f).map { |v| [v, display_one(v, f)] } },
          active: active?(from: date_of(ds, from_field), to: date_of(ds, to_field), as_of: as_of),
          sort_date: date_of(ds, from_field)
        )
      end
      rows = sort_rows(rows)

      summary = summarize(datasets: datasets, sum_field: sum_field, from_field: from_field, to_field: to_field,
                          expected_total: declaration[:expected_total], tolerance: declaration[:tolerance], as_of: as_of)

      Panel.new(
        title: declaration[:title].to_s, related_form: related_form,
        related_form_label: declaration[:related_form_label].to_s, columns: columns.map { |f| f[:label] },
        fields: columns, rows: rows,
        sum_label: sum_field && sum_field[:label],
        add_path: "/cbgp/dataset/#{related_form}",
        # So "add a new ..." opens with the link back to this record already filled in
        # (the related form's xref field = this record's key) - e.g. a new commitment
        # for the member whose page it was clicked on.
        prefill: keys.first ? { via_class => keys.first } : {},
        as_of: as_of, subject: subject_label(via_field, keys.first),
        **summary
      )
    end
    private_class_method :build_panel

    # Related records whose via field really holds one of +keys+. The search
    # may match more loosely than equality (substring, accent-folding), and
    # attaching someone else's allocations to a record is far worse than
    # missing one, so every hit is re-checked for an exact match.
    def self.related_datasets(related_form:, via_field:, keys:)
      return [] if keys.empty?

      dbname = get_dbname_for_form(form: related_form)
      wanted = keys.map { |k| k.to_s.strip.downcase }
      graphs = keys.flat_map do |key|
        execute_search(search_params: { via_field[:questionclass] => key }, dataset_type: dbname)
      end.uniq

      graphs.filter_map do |graph|
        ds = load_related(graph: graph, form: related_form)
        next unless ds

        held = values_of(ds, via_field).map { |v| v.to_s.strip.downcase }
        ds if (held & wanted).any?
      end
    end
    private_class_method :related_datasets

    # load_from_graph +abort+s (SystemExit) rather than raising when a graph
    # has no primary id; a display panel must not take the whole page down
    # for one malformed neighbour.
    def self.load_related(graph:, form:)
      CBGP::Dataset.load_from_graph(graph: graph, database: form)
    rescue StandardError, SystemExit => e
      warn "[RELATED-RECORDS] could not load #{graph}: #{e.class}: #{e.message}"
      nil
    end
    private_class_method :load_related

    def self.columns_for(declaration:, related_fields:)
      wanted = get_related_records_columns_query(panel: fragment(declaration[:panel])).map { |r| fragment(r[:column]) }
      related_fields.select { |f| wanted.include?(f[:questionclass]) } # fields_for is already in question-order
    end
    private_class_method :columns_for

    # Whether a record applies on +as_of+; either bound being blank means
    # unbounded on that side (an open-ended allocation has no end date).
    def self.active?(from:, to:, as_of:)
      (from.nil? || from <= as_of) && (to.nil? || to >= as_of)
    end

    # Totals +sum_field+ over the records active on +as_of+, and decides the
    # warning - which looks at today AND at every FUTURE date a record starts or
    # stops applying, not just today. A commitment that starts next month is
    # invisible to a today-only check, so a person at 100% now but 110% from
    # the 14th would show no warning until the 14th; the point of the warning is
    # to be seen while it can still be fixed. Past periods are not checked
    # (not actionable). Pure: takes already-loaded data, so the rules are
    # testable without a triple store.
    #
    # @param datasets [Array<CBGP::Dataset>] the related records
    # @return [Hash] +:total+ (as of +as_of+), +:expected_total+, +:tolerance+,
    #   +:active_count+ (as of +as_of+), +:issues+ (each +{date:, total:}+: a
    #   date the active total is off, listing only where it changes) and
    #   +:warning+ (any issues). All nil/empty when there is no sum field.
    def self.summarize(datasets:, sum_field:, from_field:, to_field:, expected_total:, tolerance:, as_of:)
      return { total: nil, expected_total: nil, tolerance: nil, active_count: 0, warning: false, issues: [] } unless sum_field

      items = datasets.map do |ds|
        { from: date_of(ds, from_field), to: date_of(ds, to_field),
          value: values_of(ds, sum_field).sum(BigDecimal(0)) { |v| decimal(v) || BigDecimal(0) } }
      end
      active_on = ->(day) { items.select { |i| active?(from: i[:from], to: i[:to], as_of: day) } }
      total_of = ->(set) { set.sum(BigDecimal(0)) { |i| i[:value] } }

      expected = decimal(expected_total)
      allowed = decimal(tolerance) || BigDecimal(0)
      today = active_on.call(as_of)

      issues = []
      if expected
        # the day after an end date is when that record stops counting
        changes = items.flat_map { |i| [i[:from], i[:to] && (i[:to] + 1)] }.compact.select { |d| d > as_of }
        previous = nil
        ([as_of] + changes).uniq.sort.each do |day|
          set = active_on.call(day)
          next if set.empty? # nobody funded from this on: not an over/under-commitment, just nothing

          sum = total_of.call(set)
          issues << { date: day, total: sum } if (sum - expected).abs > allowed && sum != previous
          previous = sum
        end
      end

      { total: total_of.call(today), expected_total: expected, tolerance: allowed, active_count: today.size,
        warning: issues.any?, issues: issues }
    end

    # Human sentences for a panel's issues ("...adds up to 110.00 from
    # 2026-10-14, expected 100.00."), shared by the record page, the save
    # notice and the search-results banner so they always agree.
    def self.warning_messages(panel)
      panel.issues.to_a.map do |issue|
        when_text = issue[:date] == panel.as_of ? 'today' : "from #{issue[:date]}"
        "Active #{panel.sum_label.to_s.downcase} adds up to #{format_currency(issue[:total].to_s('F'))} #{when_text}, " \
          "expected #{format_currency(panel.expected_total.to_s('F'))}."
      end
    end

    # The same warnings for a whole page of search results: for forms that are
    # the RELATED form of a panel with an expected total (commitments: the
    # sibling panel), one check per distinct key value (per member), however
    # many of its records are in the results. Capped so a large result set
    # cannot turn one search into hundreds of lookups; the caller is told how
    # many were not checked. Forms that are not the related side of such a
    # panel (e.g. Member, whose panel lists OTHER records) are deliberately
    # skipped: that would be one panel per row.
    #
    # @return [Hash] +:messages+ (Array of String, each naming the subject) and
    #   +:skipped+ (distinct keys not checked because of +limit+)
    def self.result_warnings(datasets:, type:, as_of: Date.today, limit: 40)
      none = { messages: [], skipped: 0 }
      return none if datasets.to_a.empty?

      declarations = get_related_records_panels_query(type: type).to_a.select do |d| # .to_a: Solutions#select means SPARQL projection
        fragment(d[:related_form]) == type && d[:key_field] && d[:expected_total]
      end
      messages = []
      skipped = 0
      declarations.each do |declaration|
        key_class = fragment(declaration[:key_field])
        representatives = datasets.group_by do |ds|
          field = ds.fields.find { |f| f[:questionclass] == key_class }
          field ? values_of(ds, field).first.to_s : ''
        end.reject { |key, _| key.empty? }.values.map(&:first)

        skipped += [representatives.size - limit, 0].max
        representatives.first(limit).each do |entry|
          panel = build_panel(entry: entry, declaration: declaration, as_of: as_of)
          next unless panel&.warning

          warning_messages(panel).each { |m| messages << "#{panel.subject || panel.title}: #{m}" }
        end
      end
      { messages: messages, skipped: skipped }
    rescue StandardError => e
      warn "[RELATED-RECORDS] result warnings unavailable: #{e.class}: #{e.message} (#{e.backtrace&.first})"
      none
    end

    # Display name of the record a panel is about (e.g. the member), from the
    # related form's cross-reference label - "Álvarez Alfageme (00831666D)".
    def self.subject_label(via_field, key)
      return nil if key.to_s.empty?

      label = CBGP::Dataset.fetch_reference_label(
        target_form: via_field[:references_target], via_class: fragment(via_field[:references_via]),
        label_method: via_field[:references_label], value: key
      )
      label.to_s.empty? ? key.to_s : "#{label} (#{key})"
    rescue StandardError
      key.to_s
    end
    private_class_method :subject_label

    # Active rows first, then newest start date first; undated last.
    def self.sort_rows(rows)
      rows.sort_by do |r|
        [r.active ? 0 : 1, r.sort_date ? -r.sort_date.jd : 0]
      end
    end
    private_class_method :sort_rows

    def self.display_value(ds, field)
      values = values_of(ds, field).map { |v| display_one(v, field) }
      values.join(', ')
    end
    private_class_method :display_value

    def self.display_one(value, field)
      if field[:references_target] && field[:references_via]
        label = CBGP::Dataset.fetch_reference_label(
          target_form: field[:references_target], via_class: fragment(field[:references_via]),
          label_method: field[:references_label], value: value
        )
        return label unless label.to_s.strip.empty?
      end
      %w[number currency].include?(field[:class]) ? format_currency(value) : value
    rescue StandardError
      value
    end
    private_class_method :display_one

    def self.values_of(record, field)
      Array(record.public_send(field[:method])).map { |v| v.to_s.strip }.reject(&:empty?)
    end
    private_class_method :values_of

    def self.date_of(record, field)
      return nil unless field

      Date.iso8601(values_of(record, field).first.to_s)
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :date_of

    def self.field_named(fields, uri)
      return nil unless uri

      fields.find { |f| f[:questionclass] == fragment(uri) }
    end
    private_class_method :field_named

    def self.decimal(value)
      return nil if value.nil? || value.to_s.strip.empty?

      BigDecimal(value.to_s)
    rescue ArgumentError
      nil
    end
    private_class_method :decimal

    def self.fragment(uri)
      uri.to_s.split('#').last
    end
    private_class_method :fragment
  end
end
