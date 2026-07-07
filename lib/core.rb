require 'pony'
require 'open3'
require 'securerandom'
require 'set'

def get_databases(type: 'Core', language: $language)
  warn 'getting databases'
  types = get_questionnaire_types_query(type: type, language: language) # [{:questionnaire_type=>"https://w3id.org/CBGP-App#add-member", :questionnaire_label=>"Add/Edit Member"}, {:questionnaire_type=>"https://w3id.org/CBGP-App#add-project", :questionnaire_label=>"Add/Edit Project"}, {:questionnaire_type=>"https://w3id.org/CBGP-App#add-publication", :questionnaire_label=>"Add/Edit Publication"}]
  types = types.map { |hash| [hash[:questionnaire_label], hash[:questionnaire_type].match(/.*#(\S+)/)[1]] }
  warn types
  types
end

def generate_questionnaire(questionnaire_type:) # questionnaire_type comes in as code only
  Questionnaire.new(questionnaire_type: questionnaire_type) # questionnaire_type comes in as just the id)
  # warn questionnaire.inspect
end

def identifier_type(id: nil)
  doi_regex = %r{^(?:https://doi\.org/|doi:)?(10\.\d{4,}(?:\.\d+)*/[^/]+)$}
  return 'doi', match[1] if match = id.match(doi_regex)

  # Return the canonical DOI (10.NNNN/identifier)

  ['db_entry', id] # Return the original identifier if not a DOI
end

# Matches a properly-formatted amount in each language's number convention:
# either no grouping separator at all (any number of digits), or grouping in
# proper 3-digit clusters; an optional decimal part of exactly 1-2 digits.
# This is deliberately strict — e.g. "2,00.0000" (en) must be *rejected*, not
# silently reinterpreted as 200.00 by stripping the comma and hoping. Without
# this check, parse_currency_input would accept almost any string containing
# digits and at most one '.', regardless of whether the grouping/decimal
# shape actually makes sense as money.
CURRENCY_INPUT_PATTERNS = {
  'en' => /\A-?(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?\z/,
  'es' => /\A-?(?:\d+|\d{1,3}(?:\.\d{3})+)(?:,\d{1,2})?\z/
}.freeze

# Parses a currency amount as typed by the user in the given UI language's
# number convention, into the canonical DB form: a plain decimal string,
# '.' separator, no thousands grouping (e.g. "1234.56").
#
#   en: "1,234.56" -> "1234.56"
#   es: "1.234,56" -> "1234.56"
#
# Rejects (returns nil for) input that doesn't actually look like a properly
# formatted amount in that language — e.g. "2,00.0000" (bad grouping *and* a
# nonsensical number of decimal digits) — rather than blindly stripping
# separators and accepting whatever Float() makes of the remainder.
#
# Used by CBGP::Dataset#coerce_value (save path, where an invalid amount
# should raise) and by build_search_query (search path, where an invalid
# amount should just be skipped) — so this returns nil on unparseable input
# rather than raising; callers decide what nil means for them.
#
# @return [String, nil] canonical decimal string, or nil if unparseable/blank
def parse_currency_input(value, language: current_language)
  text = value.to_s.strip
  return nil if text.empty?

  pattern = CURRENCY_INPUT_PATTERNS[language] || CURRENCY_INPUT_PATTERNS['en']
  return nil unless pattern.match?(text)

  normalized = language == 'es' ? text.delete('.').tr(',', '.') : text.delete(',')
  format('%.2f', Float(normalized))
rescue ArgumentError
  nil
end

# Formats a canonical DB decimal string (see parse_currency_input) for
# display/export in the given UI language's number convention.
#
#   en: "1234.56" -> "1,234.56"
#   es: "1234.56" -> "1.234,56"
#
# If value isn't actually in canonical form (e.g. we're redisplaying a user's
# invalid raw input after a ValidationError, or stored data is somehow
# corrupt), it's returned unchanged rather than mangled — so the user always
# sees exactly what they typed when there's something to fix.
#
# @return [String] formatted amount, unchanged input, or '' if value is blank
def format_currency(value, language: current_language)
  text = value.to_s.strip
  return '' if text.empty?

  negative = text.start_with?('-')
  body = text.sub(/\A-/, '')
  return text unless body.match?(/\A\d+(\.\d+)?\z/)

  whole, fraction = body.split('.', 2)
  fraction = (fraction || '00').ljust(2, '0')[0, 2]
  grouped = whole.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse

  thousands_sep, decimal_sep = language == 'es' ? ['.', ','] : [',', '.']
  grouped = grouped.tr(',', thousands_sep)

  "#{'-' if negative}#{grouped}#{decimal_sep}#{fraction}"
end

# Answer-block IDs that mean "free entry" rather than "controlled
# vocabulary" — see QuestionnaireAnswerBlock in lib/questionnaire.rb, which
# special-cases the same four IDs for the same reason.
FREE_TEXT_ANSWER_BLOCKS = %w[FREE NUM DATE HIDDEN].freeze

# True if this field's widget is backed by a controlled vocabulary (select,
# radio, checkbox list, or tree-selector) rather than free text/number/date
# entry — i.e. the value actually stored is an ontology class ID (e.g.
# "usa"), not a human-readable string.
def controlled_vocabulary_field?(field)
  ablockid = field[:answers].to_s.split('#').last
  !ablockid.to_s.empty? && !FREE_TEXT_ANSWER_BLOCKS.include?(ablockid)
end

# Memoized wrapper around get_label_for_id (lib/queries.rb) — a search
# results page can call this once per (field, row), so caching avoids
# re-parsing/re-executing the same SPARQL lookup for repeated values (e.g.
# the same country or status appearing across many rows).
LABEL_LOOKUP_CACHE = {} # rubocop:disable Style/MutableConstant -- intentionally mutated as a cache

def cached_label_for_id(id:, language: current_language)
  key = "#{id}_#{language}"
  LABEL_LOOKUP_CACHE.fetch(key) { LABEL_LOOKUP_CACHE[key] = get_label_for_id(id: id, language: language) }
end

# Resolves a single stored field value for display: currency amounts are
# locale-formatted (see format_currency); controlled-vocabulary values (e.g.
# "usa") are resolved to their current-language rdfs:label (e.g. "United
# States of America"); anything else (free text, dates, ORCiDs, …) is passed
# through unchanged. Falls back to the raw stored value if no label is found
# (e.g. a since-removed ontology class), so a lookup miss never makes data
# disappear from the results.
#
# @param field [Hash] a field descriptor from CBGP::Dataset.fields_for
# @param value [Object] one stored value for that field (not an Array —
#   callers handle Multiple-cardinality fields by mapping this over each one)
# @return [String] the value as it should be displayed/exported
def resolve_display_value(field, value)
  return format_currency(value) if field[:class] == 'currency'
  return value.to_s unless controlled_vocabulary_field?(field)

  cached_label_for_id(id: value) || value.to_s
end

# True if a field value should be treated as "no value" — nil, an empty
# array/string, or a string that's blank once stripped.
def blank_field_value?(value)
  return true if value.nil?
  return value.empty? if value.respond_to?(:empty?)

  value.to_s.strip.empty?
end

# True if two stored field values are the same, ignoring only the order of a
# Multiple-cardinality field's array (re-ordering isn't a real change) and
# treating any blank shape (nil/""/[]) as equal to any other.
def field_values_equal?(old_value, new_value)
  return true if blank_field_value?(old_value) && blank_field_value?(new_value)

  Array(old_value).map(&:to_s).sort == Array(new_value).map(&:to_s).sort
end

# Renders a field value for the change-summary heuristic below: "(none)" for
# blank, otherwise each value through resolve_display_value (so currency and
# controlled-vocabulary values read the same way here as everywhere else).
def display_field_value_or_none(field, value)
  return '(none)' if blank_field_value?(value)

  Array(value).map { |v| resolve_display_value(field, v) }.join(', ')
end

# Builds the SCD Type 2 "history-detail" heuristic: a human-readable, one
# line per changed field summary of what an edit changed, e.g.
# "Total funding: 15,000.00 → 20,000.00; PI ORCiD: (none) → 0000-0001-2345-6789".
# Unchanged fields are omitted entirely. This is a straightforward
# field-by-field diff, not a semantic understanding of the data — good
# enough to see what changed at a glance.
#
# @param fields [Array<Hash>] field descriptors, e.g. dataset.fields
# @param old_values [Hash] questionclass Symbol => prior value, as returned
#   by fetch_datasets_raw_data (lib/queries.rb)
# @param new_dataset [CBGP::Dataset] the dataset with its new values already set
# @return [String] semicolon-separated change summary, or '' if nothing changed
def summarize_field_changes(fields:, old_values:, new_dataset:)
  fields.filter_map do |field|
    next unless field[:method]

    old_value = old_values[field[:questionclass].to_sym]
    new_value = new_dataset.public_send(field[:method])
    next if field_values_equal?(old_value, new_value)

    old_display = display_field_value_or_none(field, old_value)
    new_display = display_field_value_or_none(field, new_value)
    "#{field[:label]}: #{old_display} → #{new_display}"
  end.join('; ')
end

def build_transitive_tree(results, abblockid:)
  abblockid = abblockid.to_s.strip
  if abblockid.empty?
    warn "Warning: abblockid is nil or empty; using default 'root'."
    abblockid = 'root'
  end
  abblockid_uri = "https://w3id.org/CBGP-App##{abblockid}"

  nodes = {}
  children = Hash.new { |h, k| h[k] = [] }

  results.each do |result|
    aid = result[:aid].to_s
    aid_fragment = aid.split('#').last
    parent = result[:parent]&.to_s
    parent_fragment = parent ? parent.split('#').last : nil

    sequence = if result[:sequence]
                 case result[:sequence]
                 when RDF::Literal::Integer, RDF::Literal::Numeric
                   result[:sequence].value.to_i
                 when RDF::Literal
                   result[:sequence].to_s.to_i
                 else
                   0
                 end
               else
                 0
               end

    # Ensure valid id and text
    next unless aid_fragment && result[:label]&.to_s

    nodes[aid] = {
      id: aid_fragment,
      text: result[:label].to_s.gsub('"', '\"').gsub(/[\n\r\t]/, ' '),
      parent: parent_fragment || '#',
      sequence: sequence
    }
    children[parent] << aid if parent
  end

  descendants = Set.new
  queue = [abblockid_uri]
  while (current = queue.shift)
    next unless children[current]

    children[current].each do |child|
      descendants << child
      queue << child
    end
  end

  root_label = get_label_for_id(id: abblockid)
  nodes[abblockid_uri] ||= {
    id: abblockid,
    text: (root_label || abblockid).gsub('"', '\"').gsub(/[\n\r\t]/, ' '),
    parent: '#',
    sequence: 0
  }
  nodes.select! { |aid, _| aid == abblockid_uri || descendants.include?(aid) }

  nodes.each do |aid, node|
    node[:parent] = '#' if node[:parent] == abblockid
  end

  nodes.each_value { |node| node[:children] = [] }
  nodes.each do |aid, node|
    next if node[:parent] == '#'

    parent_node = nodes["https://w3id.org/CBGP-App##{node[:parent]}"]
    parent_node[:children] << node if parent_node
  end

  nodes.values.select { |n| n[:parent] == '#' }.sort_by { |n| n[:sequence] }
  # warn "Tree: #{tree.inspect}"
end

def nest_children(node, nodes)
  node[:children] = nodes.values.select { |n| n[:parent] == node[:id] }
  node[:children].each { |child| nest_children(child, nodes) }
end
