require_relative 'queries'
require_relative 'core'

class Questionnaire
  attr_accessor :questionnaire_type, :sections, :questionnaireid

  @@cache = {} # OPTIMIZATION: Class-level cache hash, keyed by questionnaire_type (e.g., "publication")

  def self.get_cached(questionnaire_type:)
    lang = current_language
    key = "#{questionnaire_type}_#{lang}"
    @@cache[key] ||= new(questionnaire_type: questionnaire_type) # new() triggers queries with current_language
  end

  # Clears the cached Questionnaire objects so the next request rebuilds
  # them from the freshly-reloaded $ontology. See CBGP::Dataset.clear_caches!
  # (same reasoning: reloading $ontology alone doesn't invalidate this).
  def self.clear_cache!
    @@cache.clear
  end

  def initialize(questionnaire_type:) # questionnaire_type  "add-publications", "add-project" "add-member"
    # GET THE LABELS HERE
    # @lang = lang.upcase
    @questionnaire_type = questionnaire_type # its GUID as only the #code

    # NOTE: on required_fields, +questionnaire_type+ here is whatever the
    # caller passed as "the form" (see app/controllers/routes.rb - the
    # add/edit routes pass @form, the true form class, e.g.
    # "personnel_project"; other routes, like search, pass @database, the
    # shared dbname). CBGP::Dataset.form_required_fields(form: ...) only
    # finds a form's local:requires-field markers if it's given the real
    # form class - for callers that only had a dbname to hand, this just
    # resolves to an empty Set (no requires-field marker on a dbname that
    # isn't also a form class), so the asterisk simply never appears there.
    # That's the correct behavior for those call sites (e.g. a search form
    # has no "required" concept), not a bug - see form_required_fields'
    # own doc comment in lib/dataset_classes.rb for the full rationale.
    @required_fields = CBGP::Dataset.form_required_fields(form: @questionnaire_type)

    # Same shape and same caveat as @required_fields above: a
    # {questionclass => Dentaku expression} Hash, resolved once per form
    # and passed down to every section/question. Empty for any caller that
    # only had a dbname to hand (no local:has-formulas on a dbname that
    # isn't also a form class) - a calculated field's widget just never
    # appears there, same graceful degradation as required_fields.
    @formulas = CBGP::Dataset.form_formulas(form: @questionnaire_type)
    @sections = get_sections
    @questionnaireid = Time.now.to_i
  end

  def get_sections
    sects = []
    warn "getting sections for #{@questionnaire_type}"
    results = get_questionnaire_sections_query(questionnaire_type: @questionnaire_type) # "add-publications", "add-project" "add-member"
    # SELECT ?sec (str(?seclab) as ?label)  WHERE {
    #   cbgp:#{questionnaire_type} local:has-fields ?sec . #  "add-publications", "add-project" "add-member"
    #   ?sec rdfs:label ?seclab .
    # warn "SECTIONS QUERY #{results.inspect}"

    results.each do |res| # get general information first
      section = res[:sec].to_s # comes in as full URI  e.g. https://w3id.org/CBGP-App#new-publication-questions
      sectionid = section.gsub(/.*\#/, '') # remove everything up to the hash in the URL
      warn "getting section #{section}" # new-publication-questions
      seclabel = res[:label].to_s
      sects << QuestionnaireSection.new(sectionid: sectionid, sectionlabel: seclabel,
                                        required_fields: @required_fields, formulas: @formulas)
      # warn "QUESTIONNAIRE SECTIONS #{sects.inspect}"
    end
    sects
  end
end

class QuestionnaireSection
  attr_accessor :sectionid, :questions, :sectionlabel, :lang, :wdo_comment, :center_response

  # required_fields: the Set<String> of questionclass fragments the current
  # form requires (built once in Questionnaire#initialize and passed down
  # to every section, since it's the same for the whole form - a field
  # doesn't become "required" or not depending on which section it's
  # displayed in). formulas: same idea, a {questionclass => expression}
  # Hash for calculated fields.
  # sectionid comes in as identifier only e.g. new-publication-questions
  def initialize(sectionid:, sectionlabel:, required_fields: Set.new, formulas: {})
    @sectionid = sectionid
    @sectionlabel = sectionlabel
    @questions = get_questions(sectionid: @sectionid, required_fields: required_fields, formulas: formulas)
    @wdo_comment = nil
    @center_response = nil
  end

  def get_questions(sectionid:, required_fields: Set.new, formulas: {})
    qs = []
    results = get_section_questions_query(sectionid: sectionid)
    # ?q (str(?qlab) as ?label) ?widget ?class ?method ?cardinality ?answers ?sequence
    results.each do |res|
      qurl = res[:q].to_s # comes in as full URL
      qid = qurl.gsub(/.*\#/, '') # everything up to the hash in the URL
      question = res[:label].to_s
      answerblock = res[:answers].to_s # check that this is a URI an dnot a fr4agtment
      ablockid = answerblock.gsub(/.*\#/, '') # everything up to the hash in the URL
      sequence = res[:sequence].to_i
      widget = res[:widget].to_s
      objectclass = res[:class].to_s
      objectmethod = res[:method].to_s
      cardinality = res[:cardinality].to_s

      references_uri = res[:references]&.to_s
      references_target = references_uri ? references_uri.gsub(/.*\#/, '') : nil # e.g. "member"
      references_via_uri = res[:references_via]&.to_s
      references_via_class = references_via_uri ? references_via_uri.gsub(/.*\#/, '') : nil # e.g. "orcid"
      references_via_label = res[:references_label]&.to_s
      references_label_method = references_via_label ? references_via_label.gsub(/.*\#/, '') : nil # e.g. "name"
      comment = res[:comment]&.to_s # mouseover help text, current language; blank if the ontology has none

      qs << QuestionnaireQuestion.new(
        questionid: qid,
        question: question,
        ablockid: ablockid,
        sequence: sequence,
        widget: widget,
        cardinality: cardinality,
        objectclass: objectclass,
        objectmethod: objectmethod,
        # NEW params:
        references_target: references_target,
        references_via_class: references_via_class,
        references_label_method: references_label_method,
        comment: comment,
        # qid is the questionclass fragment (e.g. "project_title") - exactly
        # what form_required_fields returns, so a plain Set#include? is all
        # that's needed to answer "does this form require this question?"
        required: required_fields.include?(qid),
        # nil for an ordinary field; a Dentaku expression string (e.g.
        # "project_overheads * 0.05") for a calculated one. Presence of
        # this, not the widget type, is what _question.erb gates the
        # read-only _calculated.erb widget on - see form_formulas' doc
        # comment in lib/dataset_classes.rb for why formulas live per-form
        # rather than on the question class itself.
        formula: formulas[qid]
      )
    end
    qs
  end
end

class QuestionnaireQuestion
  attr_accessor :questionid, :sequence, :objectclass, :objectmethod, :ablockid, :answertree, :question, :selected_answer,
                :widget, :cardinality, :answerblock,
                :references_target, :references_via_class, :references_label_method, :comment, :required, :formula

  def initialize(questionid:, sequence:, objectclass:, objectmethod:, ablockid:, question:,
                 widget:, cardinality:, references_target: nil, references_via_class: nil, references_label_method: nil,
                 comment: nil, required: false, formula: nil)
    @question = question
    @comment = comment
    # required: true if THIS form (see Questionnaire#initialize) marks this
    # question's questionclass with local:requires-field. Read by
    # app/views/_question.erb to render the red asterisk visual cue - the
    # actual enforcement (rejecting a save if it's blank) lives server-side
    # in CBGP::Dataset.load_from_params_and_write, this flag is display-only.
    @required = required
    # formula: nil for an ordinary field; a Dentaku expression string for a
    # calculated one (see local:has-formulas). Read by _question.erb to
    # decide whether to render the read-only _calculated.erb widget instead
    # of the field's ordinary one. Like +required+, this is display-only -
    # the server-side computation in CBGP::Dataset.evaluate_calculated_fields
    # is what's actually authoritative.
    @formula = formula
    @questionid = questionid # this is the ontology class (e.g. cbgp:mem1  becomes questionid = "mem1")
    @sequence = sequence
    @widget = widget.downcase
    @objectclass = objectclass
    @objectmethod = objectmethod
    @cardinality = cardinality
    @ablockid = ablockid # This sets the instance variable
    @selected_answer = nil
    @answertree = nil
    @answerblock = QuestionnaireAnswerBlock.new(ablockid: @ablockid)

    # NEW: store reference info
    @references_target = references_target # e.g. "member"
    @references_via_class = references_via_class # e.g. "orcid"
    @references_label_method = references_label_method # e.g. "surname"
    # warn "WIDGET IS #{@widget}"
    return unless @widget.match(/TreeSelector/i)

    @answertree = get_hierarchical_answer_block_query(ablockid: @ablockid) # Fixed: use @answerblockid
    @answertree = JSON.parse(@answertree)
    # Optional: Sanitize curly quotes...
    @answertree.each do |node|
      node['text'] = node['text'].gsub(/[“”‘’]/, '"') if node['text']
      node['children']&.each { |child| child['text'] = child['text'].gsub(/[“”‘’]/, '"') if child['text'] }
    end
    warn "Hierarchical Data: #{@answertree.inspect}"
  end

  # The questionclass fragments this question's formula references (e.g.
  # +["project_overheads"]+ for "project_overheads * 0.05"), used by
  # app/views/_calculated.erb to attach a live-preview JS listener to each
  # dependency's input element. Just a bare identifier scan - deliberately
  # NOT filtered against the form's real field list (nothing here needs
  # that precision): the widget only ever uses this to look up DOM elements
  # by ID, and a token that doesn't match a real field simply finds no
  # element and is silently skipped. The one thing server-side evaluation
  # (CBGP::Dataset.evaluate_calculated_fields) actually treats as
  # authoritative never uses this method at all.
  def formula_dependencies
    return [] if @formula.to_s.strip.empty?

    @formula.scan(/[A-Za-z_][A-Za-z0-9_]*/).uniq
  end
end

class QuestionnaireAnswerBlock
  attr_accessor :ablockid, :answers, :type

  def initialize(ablockid:) # answer ablockid comes in as fragment only
    @ablockid = ablockid
    @answers = []

    if @ablockid == 'FREE' # a text box or text field
      @type = 'FREE'
    elsif @ablockid == 'NUM' # text field numerical
      @type = 'NUM'
    elsif @ablockid == 'DATE' # text field numerical
      @type = 'DATE'
    elsif @ablockid == 'HIDDEN' # text field numerical
      @type = 'HIDDEN'
    else
      results = get_answer_block_query(ablockid: @ablockid) #    SELECT DISTINCT ?aid ?label ?order
      results.each do |result|
        answers << QuestionnaireAnswer.new(answerid: result[:aid].to_s, answer: result[:label].to_s,
                                           sequence: result[:sequence].to_i)
      end
    end
  end
end

class QuestionnaireAnswer
  attr_accessor :answerid, :answer, :lang, :sequence

  def initialize(answerid:, answer:, sequence:)
    @answerid = answerid
    @answerid = @answerid.gsub(/.*\#/, '') # everything up to the hash in the URL
    @sequence = sequence
    @answer = answer
  end
end

class QuestionnaireField
  attr_accessor :fieldid, :label, :answerblock, :answertree, :objectclass, :objectmethod, :questionorder, :cardinality,
                :widgettype

  def initialize
  end

  def self.create_from_ontology(fieldid:)
    field = QuestionnaireField.new
    res = field_query(fieldid: fieldid).first # should only be one
    return nil unless res

    field.fieldid = fieldid.to_s # this is the class name of that question in teh ontlogy.  e.g. cbgp:mem1  the fieldid is "mem1"

    field.label = res[:label].to_s
    field.objectclass = res[:objectclass].to_s
    field.objectmethod = res[:objectmethod].to_s
    field.questionorder = res[:questionorder].to_s
    field.cardinality = res[:cardinality].to_s

    field.widgettype = res[:widgettype].to_s
    field.answerblock = res[:answerblock].to_s
    if field.widgettype.match(/TreeSelector/i)
      field.answertree = get_hierarchical_answer_block_query(ablockid: field.answerblock)
      field.answertree = JSON.parse(field.answertree) # Now it's an array of hashes
      # Optional: Sanitize curly quotes if visuals glitch (JS handles unicode fine, but for safety)
      field.answertree.each do |node|
        node['text'] = node['text'].gsub(/[“”‘’]/, '"') if node['text'] # Straight quotes
        next unless node['children']

        node['children'].each do |child|
          child['text'] = child['text'].gsub(/[“”‘’]/, '"') if child['text']
        end
      end
      warn "Hierarchical Data: #{field.answertree.inspect}"
    end
    field
  end
end
