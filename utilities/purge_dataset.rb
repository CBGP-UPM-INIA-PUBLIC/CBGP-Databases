#!/usr/bin/env ruby
# frozen_string_literal: true

require 'dotenv'
Dotenv.load(File.expand_path('../.env', __dir__)) # the project root's .env, not a separate utilities/.env copy - avoids config drift like the Virtuoso migration missing this file (2026-08-26)
require 'require_all'
require_all '../app'
abort "must provide dataset type e.g. member" unless ARGV[0]

graphs = search_for_all_graphs(dataset_type: ARGV[0].strip)

graphs.each do |g|
  delete_dataset_query(oldid: g)
end
