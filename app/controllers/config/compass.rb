if defined?(Sinatra)
  # This is the configuration to use when running within sinatra
  project_path = Sinatra::Application.root
  css_dir = File.join 'public', 'stylesheets'
  relative_assets = true
  environment = :development
else
  # this is the configuration to use when running within the compass command line tool.
  css_dir = File.join 'public', 'stylesheets'
  relative_assets = true
  environment = :production
end