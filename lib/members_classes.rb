require_relative 'queries'
require_relative 'core'

module CBGP
  class Member
    
    def initialize()
      @uniqid = Time.now.to_i unless uniqid.match(/S/)
    end
  end
end
