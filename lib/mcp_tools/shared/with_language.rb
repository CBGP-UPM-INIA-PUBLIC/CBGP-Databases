# frozen_string_literal: true

module McpTools
  module Shared
    # Scopes current_language (Thread.current[:language], lib/core.rb) to
    # the duration of one MCP tool call. The human web app sets this from
    # session[:language] in routes.rb's `before` filter; an MCP call has no
    # session, so callers pass the language explicitly instead - the agent
    # is expected to detect it from the user's question and pass it as a
    # tool argument, not something this codebase tries to detect itself.
    #
    # Reused by any tool that returns ontology rdfs:label text
    # (list_form_facets, ontology_relationships). Tools that only return raw
    # stored data or questionclass identifiers (search_records, get_record,
    # aggregate, every History-server tool) don't need this at all - that
    # output is never translated in the first place.
    #
    # Always restores whatever Thread.current[:language] held before the
    # call, so one MCP request's language choice can never leak into a
    # later, unrelated request sharing the same thread.
    module WithLanguage
      def self.call(language)
        previous = Thread.current[:language]
        Thread.current[:language] = language.to_s.empty? ? 'en' : language
        yield
      ensure
        Thread.current[:language] = previous
      end
    end
  end
end
