# frozen_string_literal: true

# Structural sanity checks over the WHOLE ontology (spec_helper resolves
# $ontology from a sibling ../CBGP-Ontology checkout -> live w3id.org ->
# committed fixture, in that order - see spec_helper.rb's
# resolve_ontology_source). This ontology is maintained by non-programmers
# (Sara), so it changes far more often than this codebase does - these
# specs exist to catch the specific ways an edit can silently break the
# interface without anyone noticing:
#
#   - A field missing a required property (widget-type, widget-cardinality,
#     answer-block, question-order) doesn't error - get_section_questions_query
#     requires all of them as non-OPTIONAL triple patterns, so the field
#     just silently vanishes from its form entirely.
#   - A field or answer option missing a label in one of the two supported
#     languages doesn't error either - it just disappears from the UI
#     whenever that language is active (FILTER(lang(?label) = "..." )).
#   - A flat (non-TreeSelector) answer option missing local:answer-order
#     vanishes from its dropdown the same way (get_answer_block_query
#     requires it as non-OPTIONAL; TreeSelector's hierarchical query does
#     not, since build_transitive_tree defaults a missing sequence to 0).
#   - A dangling widget-type/answer-block/subClassOf reference (pointing at
#     a class that doesn't exist) breaks silently rather than raising.
#
# None of this is about whether the ontology's CONTENT is correct (that's
# Sara's domain expertise, not ours) - only whether it has the structural
# shape this codebase's queries assume.
RSpec.describe 'Ontology structural sanity' do
  # local: -> urn:local: (see PREFIXES, lib/queries.rb) - LOCAL_NS is
  # already defined by lib/history_queries.rb, loaded via spec_helper.
  # Methods, not top-level constants (Lint/ConstantDefinitionInBlock) -
  # this is all inside an RSpec.describe block.
  def method_prop
    RDF::URI("#{LOCAL_NS}method")
  end

  def widget_type_prop
    RDF::URI("#{LOCAL_NS}widget-type")
  end

  def widget_cardinality_prop
    RDF::URI("#{LOCAL_NS}widget-cardinality")
  end

  def answer_block_prop
    RDF::URI("#{LOCAL_NS}answer-block")
  end

  def question_order_prop
    RDF::URI("#{LOCAL_NS}question-order")
  end

  def answer_order_prop
    RDF::URI("#{LOCAL_NS}answer-order")
  end

  def free_text_blocks
    %w[FREE NUM DATE HIDDEN]
  end

  def supported_languages
    %w[en es]
  end

  def frag(uri)
    uri.to_s.split('#').last
  end

  def cbgp_uri(local_name)
    RDF::URI("#{CBGP_NS}#{local_name}")
  end

  def label_languages(subject)
    $ontology.query([subject, RDF::RDFS.label, nil]).filter_map { |s| s.object.language&.to_s }
  end

  def questionclass_subjects
    $ontology.query([nil, method_prop, nil]).map(&:subject).uniq
  end

  def direct_children(parent_uri)
    $ontology.query([nil, RDF::RDFS.subClassOf, parent_uri]).map(&:subject).uniq
  end

  def transitive_descendants(root_uri)
    seen = []
    queue = [root_uri]
    until queue.empty?
      current = queue.shift
      direct_children(current).each do |child|
        next if seen.include?(child)

        seen << child
        queue << child
      end
    end
    seen
  end

  def class_defined?(uri)
    $ontology.query([uri, nil, nil]).any? # has at least one outgoing triple, i.e. is actually defined somewhere
  end

  describe 'every field (has local:method)' do
    it 'has all properties get_section_questions_query requires (widget-type, widget-cardinality, answer-block, question-order) plus an English and Spanish label' do
      violations = questionclass_subjects.filter_map do |subject|
        missing = []
        missing << 'widget-type' if $ontology.query([subject, widget_type_prop, nil]).none?
        missing << 'widget-cardinality' if $ontology.query([subject, widget_cardinality_prop, nil]).none?
        missing << 'answer-block' if $ontology.query([subject, answer_block_prop, nil]).none?
        missing << 'question-order' if $ontology.query([subject, question_order_prop, nil]).none?

        langs = label_languages(subject)
        (supported_languages - langs).each { |lang| missing << "#{lang} label" }

        "#{frag(subject)}: missing #{missing.join(', ')}" unless missing.empty?
      end

      expect(violations).to eq([]), "Fields with missing required properties:\n#{violations.join("\n")}"
    end

    it 'only ever uses widget-cardinality "Single" or "Multiple"' do
      violations = questionclass_subjects.filter_map do |subject|
        values = $ontology.query([subject, widget_cardinality_prop, nil]).map { |s| s.object.to_s }
        bad = values - %w[Single Multiple]
        "#{frag(subject)}: #{bad.join(', ')}" unless bad.empty?
      end

      expect(violations).to eq([]), "Fields with an unrecognized widget-cardinality:\n#{violations.join("\n")}"
    end

    it 'never points widget-type or answer-block at an undefined class (free-text answer-blocks excepted)' do
      violations = questionclass_subjects.filter_map do |subject|
        problems = []

        $ontology.query([subject, widget_type_prop, nil]).each do |s|
          problems << "widget-type '#{frag(s.object)}' is not defined" unless class_defined?(s.object)
        end

        $ontology.query([subject, answer_block_prop, nil]).each do |s|
          next if free_text_blocks.include?(frag(s.object))

          problems << "answer-block '#{frag(s.object)}' is not defined" unless class_defined?(s.object)
        end

        "#{frag(subject)}: #{problems.join('; ')}" unless problems.empty?
      end

      expect(violations).to eq([]), "Fields pointing at an undefined class:\n#{violations.join("\n")}"
    end
  end

  describe 'every answer option (a value a field can actually be set to)' do
    it 'has an English and Spanish label, and (for flat, non-TreeSelector fields) an answer-order' do
      violations = []

      questionclass_subjects.each do |subject|
        answer_block = $ontology.query([subject, answer_block_prop, nil]).first&.object
        next unless answer_block && !free_text_blocks.include?(frag(answer_block))

        widget_type = $ontology.query([subject, widget_type_prop, nil]).first&.object
        is_tree = widget_type && frag(widget_type) == 'TreeSelector'
        options = is_tree ? transitive_descendants(answer_block) : direct_children(answer_block)

        options.each do |opt|
          missing = []
          langs = label_languages(opt)
          (supported_languages - langs).each { |lang| missing << "#{lang} label" }
          missing << 'answer-order' if !is_tree && $ontology.query([opt, answer_order_prop, nil]).none?

          next if missing.empty?

          violations << "#{frag(subject)} -> #{frag(answer_block)} (#{is_tree ? 'TreeSelector' : 'flat'}) option '#{frag(opt)}': missing #{missing.join(', ')}"
        end
      end

      expect(violations).to eq([]), "Answer options with missing required properties:\n#{violations.join("\n")}"
    end

    it 'is never orphaned - every non-free-text answer-block actually has at least one option' do
      violations = questionclass_subjects.filter_map do |subject|
        answer_block = $ontology.query([subject, answer_block_prop, nil]).first&.object
        next if answer_block.nil? || free_text_blocks.include?(frag(answer_block))

        widget_type = $ontology.query([subject, widget_type_prop, nil]).first&.object
        is_tree = widget_type && frag(widget_type) == 'TreeSelector'
        options = is_tree ? transitive_descendants(answer_block) : direct_children(answer_block)

        "#{frag(subject)} -> answer-block '#{frag(answer_block)}' has zero options" if options.empty?
      end

      expect(violations).to eq([]), "Fields whose answer-block has no options:\n#{violations.join("\n")}"
    end
  end

  it 'never defines the same rdfs:label twice for the same language on the same class (ambiguous for FILTER(lang(...))-based lookups)' do
    # 'forms' is a known, pre-existing case (found 2026-09-25, not introduced
    # by any change in this codebase) - it has two English labels ("Data
    # entry" and "Forms"). Low real-world impact since 'forms' is a purely
    # structural/internal marker class (get_dbname_for_form's
    # `rdfs:subClassOf cbgp:forms` check) never shown to a user directly,
    # but it's a real ontology data-quality issue flagged to the team.
    # Remove this allowance once it's cleaned up upstream.
    known_issues = %w[forms].freeze

    by_subject = Hash.new { |h, k| h[k] = [] }
    $ontology.query([nil, RDF::RDFS.label, nil]).each { |s| by_subject[s.subject] << s.object }

    violations = by_subject.filter_map do |subject, labels|
      next if known_issues.include?(frag(subject))

      dupes = labels.group_by { |l| l.language&.to_s }.select { |lang, vals| lang && vals.size > 1 }
      next if dupes.empty?

      "#{frag(subject)}: #{dupes.map { |lang, vals| "#{lang} has #{vals.size} labels (#{vals.map(&:to_s).join(' / ')})" }.join('; ')}"
    end

    expect(violations).to eq([]), "Classes with ambiguous duplicate-language labels:\n#{violations.join("\n")}"
  end

  it 'never leaves an rdfs:subClassOf pointing at an undefined class' do
    violations = $ontology.query([nil, RDF::RDFS.subClassOf, nil]).filter_map do |s|
      next if class_defined?(s.object)

      "#{frag(s.subject)} -> subClassOf undefined class '#{frag(s.object)}'"
    end.uniq

    expect(violations).to eq([]), "Dangling subClassOf references:\n#{violations.join("\n")}"
  end
end
