require_relative './queries'
require_relative './core'

module CBGP
  class Funding
    attr_accessor :name, :email, :applicant, :country, :id, :graph, :status, :visibility

    def initialize(name:, email:, applicant:, country:, status: 'OPEN', visibility: 'visible', id: nil, graph: nil)
      # GET THE LABELS HERE
      @name = name
      @email = email
      @applicant = applicant
      @country = country
      @id = id
      @graph = graph
      @status = status
      @visibility = visibility

      @id = Time.now.to_i unless id
    end

    def write_to_db
      write_center_to_db(center: self)
    end
  end
end
