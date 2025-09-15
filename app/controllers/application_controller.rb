require 'json'
require 'jsonpath'
require 'sinatra/base'
require 'require_all'
require 'rest-client'
require 'sanitize'
require 'httparty'

# App specific requires
require_relative 'configuration'
require_relative 'routes'
require_relative 'helpers'

require_rel '../../lib'
require_rel '../views'

module CBGP
  $language = 'en'

  class DatabasesApp < Sinatra::Base
    helpers MyHelpers
    set_routes
  end
end

CBGP::DatabasesApp.run! if __FILE__ == $0
