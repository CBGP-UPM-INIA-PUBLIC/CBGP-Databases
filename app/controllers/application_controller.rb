
require 'json'
require 'jsonpath'
require 'sinatra/base'
require 'require_all'
require 'rest-client'

# App specific requires
require_relative 'configuration'
require_relative 'routes'
require_rel '../../lib'
require_rel '../views'

module CBGP

  class DatabasesApp < Sinatra::Base
    # before do
    #   puts "Request Host: #{request.host}"
    #   puts "Full ENV: #{request.env.inspect}"
    # end
    # Debug middleware
    # puts "Middleware: #{middleware.map(&:inspect).join(', ')}" if ENV['DEBUG']
    # disable :protection  # Explicitly disable any protection
    set_routes
  end
end

CBGP::DatabasesApp.run! if __FILE__ == $0
