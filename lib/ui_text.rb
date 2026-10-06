# frozen_string_literal: true

# Interface text in the user's language (English or Spanish): the hints inside
# boxes and the captions of small buttons. Like every other label in this
# application they live in the ONTOLOGY, not in code - each piece of text is a
# subclass of cbgp:ui-text (class name "ui_" + the key with dots as
# underscores, e.g. key "typeahead.hint" => cbgp:ui_typeahead_hint) whose
# rdfs:label in each language is what the user reads, so the people who
# maintain the ontology can change or translate a text without a programmer.
#
# A %{name} in a text is filled in here from the values the caller passes. A
# text missing in the current language falls back to English, and one missing
# altogether shows its key - a visible gap on the page, never an exception.
# check_ontology.rb (in CBGP-Ontology) guards the placeholders.
module CBGP
  module UIText
    @cache = {}

    def self.clear_cache!
      @cache.clear
    end

    # The class name that holds the text for +key+.
    def self.class_name(key)
      "ui_#{key.to_s.tr('.', '_')}"
    end

    def self.label(key, language)
      id = class_name(key)
      lang = language.to_s
      return nil unless id.match?(/\A\w+\z/) && lang.match?(/\A[a-z]{2,3}\z/)

      cache_key = [id, lang]
      return @cache[cache_key] if @cache.key?(cache_key)

      found = SPARQL.parse(<<~SPARQL).execute($ontology).first
        #{PREFIXES}
        SELECT ?label WHERE { cbgp:#{id} rdfs:label ?label . FILTER (lang(?label) = '#{lang}') } LIMIT 1
      SPARQL
      text = found && found.bound?(:label) ? found[:label].to_s : nil
      @cache[cache_key] = text unless text.nil? # a miss is not remembered: the ontology may gain the text
      text
    end

    def self.translate(key, language, vars = {})
      text = label(key, language) || label(key, 'en')
      return key.to_s if text.nil?

      text.gsub(/%\{(\w+)\}/) { vars.fetch(Regexp.last_match(1).to_sym) { "%{#{Regexp.last_match(1)}}" }.to_s }
    end
  end
end

# The interface string +key+ in the current language, with %{name}
# placeholders filled from +vars+. NOT HTML-escaped - escape it where it is
# printed (CGI.escapeHTML), like any other text.
def ui_text(key, language: current_language, **vars)
  CBGP::UIText.translate(key, language, vars)
end
