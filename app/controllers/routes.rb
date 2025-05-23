# frozen_string_literal: false

require 'compass' # gives us sass/scss
require 'json'
require_relative '../../lib/core'

def set_routes
  # Compass.add_project_configuration(File.join(Sinatra::Application.root, "config", "compass.rb"))

  configure do
    set :bind, '0.0.0.0'  # Bind to all interfaces
    set :port, 4567       # Explicitly set the port (optional, since 4567 is your target)
    set :server_settings, timeout: 180
    set :root, File.dirname(__FILE__)
    set :views, proc { File.join(root, '../views') }
    set :public_folder, File.join(root, '../public')
    set :haml, { format: :html5, escape_html: true }
    set :scss, { style: :compact, debug_info: false }
    set :static_cache_control, [:public, { max_age: 0 }]
    set :session_secret, CBGP_SECRET
    enable :sessions
    use Rack::Session::Cookie, key: 'rack.session', secret: CBGP_SECRET
  end

  helpers do
    def logged_in?
      session[:username]
    end

    def current_user
      session[:username]
    end

    def scss(template, options = {})
      # Render SCSS using Compass
      Compass.sass_engine_options[:load_paths] ||= []
      Compass.sass_engine_options[:load_paths] << File.join(settings.root, 'stylesheets')
      render :scss, template, options
    end
  end

  get '/cbgp/stylesheets/:name.css' do
    content_type 'text/css', charset: 'utf-8'
    scss(:"stylesheets/#{params[:name]}")
  end

  # ----------------------------------------------------------------------------
  # ----------------------------------------------------------------------------
  # ----------------------------------------------------------------------------
  # ----------------------------------------------------------------------------
  # ----------------------------------------------------------------------------
  #  LOGIN FUNCTIONS

  get '/cbgp/login' do
    erb :login
  end

  post '/cbgp/login' do
    username = params[:username]
    password = params[:password]

    if USERS[username] == password
      session[:username] = username
      redirect '/cbgp/dashboard'
    else
      @error = 'Invalid username or password.'
      erb :login
    end
  end

  get '/cbgp/logout' do
    session.clear
    redirect '/cbgp/login'
  end

  before do
    public_paths = [
      '/', # Usually the login page
      '/cbgp/login', # Login page
      '/cbgp/stylesheets/cbgp.css', # Login page
      '/logout' # Optional: logout route
    ]

    # Skip authentication check for public paths
    return if public_paths.include?(request.path_info)

    halt(401, erb(:unauthorized)) unless logged_in?
    cache_control :public, :must_revalidate, max_age: 0
  end

  # ----------------------------------------------------------------------------
  # ----------------------------------------------------------------------------
  # ----------------------------------------------------------------------------
  # ----------------------------------------------------------------------------
  # ----------------------------------------------------------------------------
  # Main Dashboard
  get '/' do
    redirect '/cbgp/dashboard'
  end

  get '/cbgp' do
    redirect '/cbgp/dashboard'
  end

  get '/cbgp/dashboard' do
    @databases = get_databases
    erb :dashboard
  end

  post '/cbgp/databases' do
    database = params[:database]
    case database
    when 'publications'
      #  redirect "/cbgp/pubs_dashboard"
      redirect '/cbgp/publications'
    when 'personnel'
      # redirect "/cbgp/mambers_dashboard"
      redirect '/cbgp/members'
    when 'projects'
      # redirect "/cbgp/projects_dashboard"
      redirect '/cbgp/projects'
    end
    halt 422
  end

  # ----------------------------------------------------------------------------
  # ----------------------------------------------------------------------------
  # ----------------------------------------------------------------------------
  # ----------------------------------------------------------------------------
  # ----------------------------------------------------------------------------
  # Pubs Dashboard and Publications

  # get "/cbgp/pubs_dashboard" do
  #   erb :pubs_dashboard
  # end

  get '/cbgp/publications' do
    doi = params[:doi]
    @questionnaire = generate_questionnaire(questionnaire_type: 'add-publication')
    @entry = if doi
               CBGP::Publication.load_from_doi(doi: doi)
             else
               CBGP::Publication.new
             end
    halt erb :publications
  end

  post '/cbgp/publications' do
    doi = params[:doi]
    @questionnaire = generate_questionnaire(questionnaire_type: 'add-publication')
    #    begin
    @entry = if doi
               CBGP::Publication.load_from_doi(doi: doi)
             else
               CBGP::Publication.new
             end
    halt erb :publications
    #    rescue StandardError => e
    #      halt 422, e.to_s
    #    end
    #    halt 403
  end

  post '/cbgp/publications/bulk' do
    dois = params[:dois]
    #    begin
    @message = (CBGP::Publication.bulk_load_from_dois(dois: dois) if dois)

    halt erb :bulkpubs
  end

  get '/cbgp/publications/bulk' do
    halt erb :bulkpubs
  end

  post '/cbgp/validate-publication' do
    @questionnaire = generate_questionnaire(questionnaire_type: 'add-publication')
    @entry = CBGP::Publication.load_from_params(params: params)
    halt erb :publications
  end

  # ----------------------------------------------------------------------------
  # ----------------------------------------------------------------------------
  # ----------------------------------------------------------------------------
  # ----------------------------------------------------------------------------
  # ----------------------------------------------------------------------------
  # Projects Dashboard

  # get "/cbgp/projects_dashboard" do
  #   erb :projects_dashboard
  # end

  get '/cbgp/projects' do
    cbgp_id = params['cbgp_id']
    @questionnaire = generate_questionnaire(questionnaire_type: 'add-project')
    @entry = if cbgp_id
               CBGP::Project.load_from_cbgp_id(cbgp_id: cbgp_id)
             else
               CBGP::Project.new
             end
    halt erb :projects
  end

  # This comes from the top part of projects.erb, wehre there's a CBGP ID field that can be posted
  post '/cbgp/projects' do
    #    begin
    cbgp_id = params['cbgp_id']
    @questionnaire = generate_questionnaire(questionnaire_type: 'add-project')
    @entry = if cbgp_id
               CBGP::Project.load_from_cbgp_id(cbgp_id: cbgp_id)
             else
               CBGP::Project.new
             end
    halt erb :projects
    #    rescue StandardError => e
    #      halt 422, e.to_s
    #    end
    #    halt 403
  end

  # This comes from the bottom part of projects.erb, the questionnaire section, posted as params
  post '/cbgp/validate-project' do
    @questionnaire = generate_questionnaire(questionnaire_type: 'add-project')
    @entry = CBGP::Project.load_from_params(params: params)
    halt erb :projects
  end
end
