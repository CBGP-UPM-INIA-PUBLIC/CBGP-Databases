require_relative './queries'
require_relative './core'

module CBGP
  class Member
    attr_accessor :uniqid, :surnames, :names, :honorific, :upmid, :nationality, :position, :grupo

    def initialize(surnames: '', names: '', honorific: '', upmid: '', grupo: '', nationality: '', position: '')
      @uniqid = Time.now.to_i unless uniqid.match(/S/)
      @surnames = surnames
      @names = names
      @honorific = honorific
      @nationality = nationality
      @position = position
      @upmid = upmid
      @grupo = grupo
    end

    def write_to_db
      write_member_to_db(center: self)
    end
  end
end
