require 'pony'
require 'open3'
require 'securerandom'

def get_databases
  warn 'getting databases'
  types = get_questionnaire_types_query # [{:questionnaire_type=>"https://w3id.org/CBGP-App#add-member", :questionnaire_label=>"Add/Edit Member"}, {:questionnaire_type=>"https://w3id.org/CBGP-App#add-project", :questionnaire_label=>"Add/Edit Project"}, {:questionnaire_type=>"https://w3id.org/CBGP-App#add-publication", :questionnaire_label=>"Add/Edit Publication"}]
  types = types.map { |hash| [hash[:questionnaire_label], hash[:questionnaire_type].match(/.*#(\S+)/)[1]] }
  warn types
  types
end

def generate_questionnaire(questionnaire_type:) # questionnaire_type comes in as code only
  Questionnaire.new(questionnaire_type: questionnaire_type) # questionnaire_type comes in as just the id)
  # warn questionnaire.inspect
end

def identifier_type(id: nil)

  doi_regex = /^(?:https:\/\/doi\.org\/|doi:)?(10\.\d{4,}(?:\.\d+)*\/[^\/]+)$/
  if match = id.match(doi_regex)
    return "doi", match[1] # Return the canonical DOI (10.NNNN/identifier)
  else
    return 'db_entry', id # Return the original identifier if not a DOI
  end
end

# Helper to construct tree from flat results
# def build_tree_from_results(results, ablockid:)
#   nodes = {}
#   ablockid_fragment = ablockid.to_s.split('#').last  # Extract fragment, e.g., "categories"

#   results.each do |result|
#     aid = result[:aid].to_s.split('#').last  # Fragment, e.g., "permanent_researcher"
#     parent = result[:parent]&.to_s&.split('#')&.last  # Parent fragment, e.g., "categories"

#     # Map the answer block ID to '#' (root) for jsTree
#     parent = '#' if parent == ablockid_fragment

#     nodes[aid] = {
#       id: aid,
#       text: result[:label].to_s,
#       parent: parent || '#',  # Default to root if no parent
#       sequence: result[:sequence]&.to_i || 0  # Default to 0 if no sequence
#     }
#   end

#   # Sort nodes by sequence for consistent ordering
#   nodes.each_value { |node| node[:children] = [] }
#   nodes.each_value do |node|
#     next if node[:parent] == '#'
#     parent_node = nodes[node[:parent]]
#     parent_node[:children] << node if parent_node
#   end

#   # Return root nodes (parent = '#'), sorted by sequence
#   tree = nodes.values.select { |n| n[:parent] == '#' }.sort_by { |n| n[:sequence] }
#   tree
# end

require 'set'

def build_transitive_tree(results, ablockid:)
  ablockid_uri = "https://w3id.org/CBGP-App##{ablockid}"
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
      text: result[:label].to_s.gsub('"', '\"').gsub(/[\n\r\t]/, ' '), # Escape quotes and newlines
      parent: parent_fragment || '#',
      sequence: sequence
    }
    children[parent] << aid if parent
  end

  descendants = Set.new
  queue = [ablockid_uri]
  while (current = queue.shift)
    next unless children[current]
    children[current].each do |child|
      descendants << child
      queue << child
    end
  end

  nodes[ablockid_uri] ||= {
    id: ablockid,
    text: (get_label_for_id(id: ablockid) || ablockid).gsub('"', '\"').gsub(/[\n\r\t]/, ' '),
    parent: '#',
    sequence: 0
  }
  nodes.select! { |aid, _| aid == ablockid_uri || descendants.include?(aid) }

  nodes.each do |aid, node|
    node[:parent] = '#' if node[:parent] == ablockid
  end

  nodes.each_value { |node| node[:children] = [] }
  nodes.each do |aid, node|
    next if node[:parent] == '#'
    parent_node = nodes["https://w3id.org/CBGP-App##{node[:parent]}"]
    parent_node[:children] << node if parent_node
  end

  tree = nodes.values.select { |n| n[:parent] == '#' }.sort_by { |n| n[:sequence] }
  warn "Tree: #{tree.inspect}"
  tree
end

# def get_hierarchical_answer_block_query(ablockid:, language: $language)
#   query = <<~GET_HIERARCHICAL_ANSWERS
#     #{PREFIXES}
#     SELECT DISTINCT ?aid ?label ?parent ?sequence WHERE {
#       { ?aid rdfs:subClassOf ?parent . }
#       UNION
#       { ?aid rdfs:label ?label . 
#       FILTER (?aid = <https://w3id.org/CBGP-App##{ablockid}>) }
#       ?aid rdfs:label ?label .
#       FILTER (lang(?label) = "#{language}")
#       OPTIONAL { ?aid local:answer-order ?sequence . }
#     } ORDER BY ?sequence
#   GET_HIERARCHICAL_ANSWERS

#   warn "HIERARCHICAL ANSWERBLOCK QUERY IS #{query}"
#   results = SPARQL.parse(query).execute(ONTOLOGY)
#   warn "Query Results: #{results.map { |r| { aid: r[:aid], parent: r[:parent], label: r[:label], sequence: r[:sequence] } }.inspect}"
#   tree = build_transitive_tree(results, ablockid: ablockid)
#   JSON.generate(tree)
# end


def nest_children(node, nodes)
  node[:children] = nodes.values.select { |n| n[:parent] == node[:id] }
  node[:children].each { |child| nest_children(child, nodes) }
end