module CBGP
  class Parsers
    def self.params_parser_publication(params:)
      pub = CBGP::Publication.new

      # deal with the authors first, since they are the odd ones out
      names = params.delete 'newpub2_NAME' # ordered list
      orcids = params.delete 'newpub2_ORCID' # ordered list
      ranks = params.delete 'newpub2_RANK' # ordered list

     
      if names
        authors = []
        names.each do |name|
          aut = CBGP::Publication::Author.new(name: name, orcid: orcids.shift, rank: ranks.shift)
          authors << aut
        end
        field = QuestionnaireField.create_from_ontology(fieldid: "newpub2") # everythign has already been stringified
        warn "adding authors #{authors}"
        pub.send("#{field.objectmethod}=", [authors])
      end

      # one day the ontology should have both subject class and object class!  Then I could auto-create
      params.each do |id, value| # id is the #fragment of the Field (e.g. Journal Name  #newpub6)
        parse_simple_field(id: id, value: value, object: pub)
      end
      pub
    end

    def self.params_parser_member(params:)
      member = CBGP::Member.new
      # one day the ontology should have both subject class and object class!  Then I could auto-create
      params.each do |id, value| # id is the #fragment of the Field (e.g. Journal Name  #newpub6)
        parse_simple_field(id: id, value: value, object: member)
      end
      member
    end

    def self.params_parser_project(params:)
      proj = CBGP::Project.new
      # one day the ontology should have both subject class and object class!  Then I could auto-create
      params.each do |id, value| # id is the #fragment of the Field (e.g. Journal Name  #newpub6)
        parse_simple_field(id: id, value: value, object: proj)
      end
      proj
    end

    def parse_simple_field(id:, value:, object:)
        field = QuestionnaireField.create_from_ontology(fieldid: id) # everythign has already been stringified
        warn "field answerblock #{field.answerblock} #{field.answerblock.class}"
        # :fieldid, :label, :answerblock, :objectclass, :objectmethod, :questionorder, :cardinality, :widgettype
        
        if field.cardinality.to_s == 'multi' # value is a list... make it a list of lists to be consistent with API
          object.send("#{field.objectmethod}=", [value])
        elsif ['https://w3id.org/CBGP-App#FREE','https://w3id.org/CBGP-App#NUM'].include? field.answerblock
          object.send("#{field.objectmethod}=", value)
        else # need to get the label - value is the fragment of the ontology identifier  e.g. oa_yes
          value = get_label_for_id(id: value)
          object.send("#{field.objectmethod}=", value)
        end
    end
  end
end
