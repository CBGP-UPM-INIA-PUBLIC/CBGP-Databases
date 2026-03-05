#!/usr/bin/env ruby
# frozen_string_literal: true

require 'dotenv/load'
require 'require_all'
require_all 'app'

graphs = search_for_all_graphs(dataset_type: 'member')

graphs.each do |g|
  delete_dataset_query(oldid: g)
end
