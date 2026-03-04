# run.rb b only this file is executed by rerun
require_relative 'app/controllers/application_controller'  

# Optional: explicit settings
#CBGP::DatabasesApp.set :port, 4567
#CBGP::DatabasesApp.set :environment, :development

# Start the server
CBGP::DatabasesApp.run!
