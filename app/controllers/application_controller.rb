require 'json'
require 'jsonpath'
require 'sinatra/base'
require 'require_all'
require 'rest-client'
require 'sanitize'
require 'httparty'
require 'cgi'

# App specific requires
require_relative 'configuration'
require_relative 'routes'

require_rel '../../lib'
require_rel '../views'

module CBGP
  class DatabasesApp < Sinatra::Base
    helpers MyHelpers
    register Sinatra::Flash
    set_routes
  end
end

def current_language
  Thread.current[:language] || 'en'
end

# CBGP::DatabasesApp.run! if __FILE__ == $0
