require 'pony'
require 'open3'
require 'securerandom'

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

require 'set'

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
