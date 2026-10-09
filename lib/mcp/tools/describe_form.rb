# frozen_string_literal: true

require_relative '../records'

module Mcp
  module Tools
    class DescribeForm < Mcp::Tool
      MAX_VALUES = 80

      tool_name 'describe_form'
      title "Describe forms and fields"
      summary "What the organisation's own data contains: list its forms, or one form's fields. Call first; other tools need these names."
      context :dataset
      description <<~TEXT
        No form: lists every form with a description of what its records are. With form: lists its fields. Each field gives:
        name (use this exact name elsewhere), label, type, multiple (true = several values allowed),
        allowed_values (fixed-list fields: id to use, label, group), links_to (the field holds the key of a record in
        another form) and help. At the end, referenced_by lists the forms whose records point at this form's records.

        Example: describe_form {"form": "member"}
      TEXT
      param :form, type: 'string', description: 'A form name from the list (omit to list all forms)'

      def self.run(args)
        ctx = Records::Context.new
        if blank?(args['form'])
          return { about: ctx.dataset_description, forms: list(ctx),
                   hint: 'Call describe_form again with one of these form names to see its fields.' }.compact
        end

        describe(ctx, ctx.form!(args['form']))
      end

      def self.list(ctx)
        ctx.forms.map do |f|
          entry = { form: f.name, label: f.label }
          entry[:description] = f.description if f.description
          entry[:storage_name] = f.storage unless f.storage == f.name
          entry
        end
      end

      def self.describe(ctx, form)
        {
          form: form.name, label: form.label,
          description: form.description,
          note: storage_note(ctx, form),
          fields: ctx.fields(form.name).map { |f| field_entry(ctx, f) },
          referenced_by: ctx.inbound_references(form.storage).map do |r|
            { form: r[:form].name, field: r[:field][:questionclass], label: r[:field][:label] }
          end
        }.compact
      end

      def self.storage_note(ctx, form)
        siblings = ctx.forms.select { |f| f.storage == form.storage && f.name != form.name }.map(&:name)
        return nil if siblings.empty?

        "Records of this form are stored together with: #{([form.name] + siblings).uniq.join(', ')} (storage name '#{form.storage}'). " \
          "Searching '#{form.storage}' covers all of them; each record says which form wrote it."
      end

      def self.field_entry(ctx, field)
        entry = { name: field[:questionclass], label: field[:label], type: type_of(field) }
        entry[:multiple] = true if ctx.multiple?(field)
        entry[:help] = field[:comment] unless blank?(field[:comment])
        values = ctx.vocabulary(field)
        unless values.empty?
          entry[:allowed_values] = values.first(MAX_VALUES)
          entry[:more_values] = values.size - MAX_VALUES if values.size > MAX_VALUES
        end
        entry[:links_to] = { form: field[:references_target], matched_on: Records.fragment(field[:references_via]) } if Records.reference_field?(field)
        entry
      end

      def self.type_of(field)
        field[:class].to_s.empty? ? 'string' : field[:class].to_s
      end
    end
  end
end
