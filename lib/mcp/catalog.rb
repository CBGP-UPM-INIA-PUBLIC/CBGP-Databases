# frozen_string_literal: true

require_relative 'records'
require_relative 'instructions'

module Mcp
  # What the model is told about the DATA, built from the ontology's own
  # descriptions (the rdfs:comment on the forms class: what the dataset is; on
  # each form: what its records are), so it knows these tools hold the
  # organisation's records - and which words ("employees", "staff") mean which
  # form - before it ever calls one. The code names nothing: a different
  # ontology gives different text.
  #
  # Cached per loaded ontology: a reload (/cbgp/refresh) replaces $ontology,
  # which changes the key, so a stale description can never outlive an edit.
  # The tool list is shared by every user and carries no language of its own,
  # so the dataset sentence is given in each supported language and the form
  # lines are English with the Spanish name in brackets; describe_form answers
  # in the language the user asked in.
  module Catalog
    SENTENCE_MAX = 220
    @cache = {}
    @lock = Mutex.new

    module_function

    # @param kind [Symbol] :dataset (what the data is) or :forms (that, plus
    #   one line per form)
    # @return [String, nil]
    def context_text(kind)
      cached([kind]) { build(kind) }
    end

    # The server instructions: the fixed rules, then what the data is.
    def instructions
      [Mcp::INSTRUCTIONS.strip, cached([:instructions]) { build(:forms) }].compact.reject(&:empty?).join("\n\n")
    end

    # The dataset sentence in each supported language (the questions arrive
    # in either, and "empleados" must meet a text that says it), then, for
    # :forms, one line per form: its name, its Spanish label and its first
    # sentence.
    def build(kind)
      by_language = Records::SUPPORTED_LANGUAGES.to_h do |language|
        [language, in_language(language) { Records::Context.new }]
      end
      lines = []
      by_language.each do |language, ctx|
        about = in_language(language) { ctx.dataset_description }
        lines << "#{language == 'en' ? 'DATA' : 'DATOS'}: #{about}" if about
      end
      lines << forms_block(by_language) if kind == :forms
      lines.compact!
      lines.empty? ? nil : lines.join("\n")
    rescue StandardError => e
      # The tool list must never fail because a description could not be read.
      warn "[MCP] catalog unavailable (#{e.class}: #{e.message})"
      nil
    end

    def forms_block(by_language)
      english = in_language('en') { by_language['en'].forms }
      spanish = in_language('es') { by_language['es'].forms }.to_h { |f| [f.name, f.label] }
      return nil if english.empty?

      lines = english.map do |f|
        label_es = spanish[f.name]
        shown = label_es && label_es != f.label ? " [#{label_es}]" : ''
        "- #{f.name}#{shown}: #{first_sentence(f.description || f.label)}"
      end
      "FORMS (pass the name as \"form\"; Spanish name in brackets):\n#{lines.join("\n")}"
    end

    def in_language(language)
      previous = Thread.current[:language]
      Thread.current[:language] = language
      yield
    ensure
      Thread.current[:language] = previous
    end

    def first_sentence(text, max = SENTENCE_MAX)
      sentence = text.to_s.strip.split(/(?<=[.!?])\s+/, 2).first.to_s
      return sentence if sentence.length <= max

      "#{sentence[0, max - 1].sub(/\s+\S*\z/, '').rstrip}…" # cut at a word, never mid-word
    end

    def cached(key)
      full_key = [$ontology.object_id] + key
      @lock.synchronize do
        @cache.clear unless @cache.keys.all? { |k| k.first == $ontology.object_id }
        return @cache[full_key] if @cache.key?(full_key)
      end
      value = yield
      @lock.synchronize { @cache[full_key] = value }
    end

    # For specs: forget everything.
    def reset!
      @lock.synchronize { @cache.clear }
    end
  end
end
