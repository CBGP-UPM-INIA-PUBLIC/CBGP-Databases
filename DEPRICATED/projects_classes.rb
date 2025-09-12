require_relative "./queries"
require_relative "./core"

module CBGP
  class Project
    attr_accessor :external_identifier, :internal_identifier, :ip_orcid, :title, :start_date, :end_date
    attr_accessor :end_date_extension, :funding_institution, :project_type, :grupo_de_investigacion
    attr_accessor :grupo_de_trabajo, :research_group, :research_group_affiliation, :total_funding, :overheads
    attr_accessor :cbgp_overheads, :annual_income, :annual_overheads, :annual_cbgp_overheads, :id

    def initialize(external_identifier: "", internal_identifier: "", ip_orcid: "", title: "", start_date: "", end_date: "", end_date_extension: "",
                   funding_institution: "", project_type: "", grupo_de_investigacion: [[]], grupo_de_trabajo: [[]], research_group: "",
                   research_group_affiliation: "", total_funding: "", overheads: "", cbgp_overheads: "", annual_income: "", annual_overheads: "",
                   annual_cbgp_overheads: "", id: nil, graph: nil)
      # GET THE LABELS HERE
      @external_identifier = external_identifier
      @internal_identifier = internal_identifier
      @ip_orcid = ip_orcid
      @title = title
      @start_date = start_date
      @end_date = end_date
      @end_date_extension = end_date_extension
      @funding_institution = funding_institution
      @project_type = project_type
      @grupo_de_investigacion = grupo_de_investigacion
      @grupo_de_trabajo = grupo_de_trabajo
      @research_group = research_group
      @research_group_affiliation = research_group_affiliation
      @total_funding = total_funding
      @overheads = overheads
      @cbgp_overheads = cbgp_overheads
      @annual_income = annual_income
      @annual_overheads = annual_overheads
      @annual_cbgp_overheads = annual_cbgp_overheads
      @id = Time.now.to_i unless id
    end

    def self.load_from_params(params:)
      #  select ?g where {graph ?g {?pub sio:SIO_000671 ?id . ?id  sio:SIO_000300 "#{doi}" ;
      pub = CBGP::Parsers.params_parser_project(params: params)
      res = retrieve_project_graph_query(doi: pub.doi)
      oldgraphid = res.first[:g].to_s if res.first
      CBGP::Publication.write_to_db(pub: pub, oldid: oldgraphid)
      pub
    end


    def write_to_db
      write_project_to_db(project: self)
    end
  end
end
