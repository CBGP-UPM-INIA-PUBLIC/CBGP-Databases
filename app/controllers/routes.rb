# frozen_string_literal: false

require 'compass' # gives us sass/scss
require 'json'
require_relative '../../lib/core'

def set_routes
  # Compass.add_project_configuration(File.join(Sinatra::Application.root, "config", "compass.rb"))

  configure do
    set :bind, '0.0.0.0'  # Bind to all interfaces
    set :port, 4567       # Explicitly set the port
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

    user_data = USERS[username]
    if user_data && user_data['password'] == password
      session[:username] = username
      role = user_data['role'] # 'admin' or 'user'
      session[:role] = role
      if role == 'user'
        redirect '/cbgp/user-dashboard'
      else
        redirect '/cbgp/dashboard'
      end
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
      '/logout', # Optional: logout route
      '/set_language' # Add the new route to public paths
      # '/cbgp/user-dashboard' # Add the new route to public paths
    ]

    # List of path prefixes that require admin (read/write) privileges
    admin_required_prefixes = [
      '/cbgp/dashboard', # Form submission / write
      '/cbgp/validate-dataset',   # Form submission / write
      '/cbgp/loaders/load',       # DOI loader (writes data)
      '/cbgp/publications/bulk'   # Bulk publication load (writes data)
    ]
    # Skip authentication check for public paths
    return if public_paths.include?(request.path_info)

    # All other paths require login
    halt(401, erb(:unauthorized)) unless session[:username]

    # Additional role check: write operations require 'admin' role
    if admin_required_prefixes.any? { |prefix| request.path_info.start_with?(prefix) } && !(session[:role] == 'admin')
      halt(403, 'Forbidden: Admin privileges required for this action.')
    end

    cache_control :public, :must_revalidate, max_age: 0
    $language = session[:language] || params[:language] || 'en'
  end

  post '/set_language' do
    session[:language] = params[:language] if %w[en es].include?(params[:language])
    status 200
  end

  get '/cbgp/refresh' do # when the ontology is updated...
    $ontology = RDF::Repository.load(CBGP_KB) # set in configuration.rb and/or in docker-compose
    redirect '/cbgp/dashboard'
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
    @databases = get_databases(type: 'Core')
    erb :dashboard
  end

  get '/cbgp/user-dashboard' do
    @databases = get_databases(type: 'UserFacing')
    erb :user_dashboard
  end

  post '/cbgp/databases' do
    form = params[:form] # database is actually the form name TODO update all cases of this
    redirect "/cbgp/dataset/#{form}"
    halt 422
  end
  post '/cbgp/user-databases' do
    form = params[:form]
    redirect "/cbgp/dataset/user-database/#{form}"
    halt 422
  end

  # ----------------------------------------------------------------------------
  # ----------------------------------------------------------------------------
  # ----------------------------------------------------------------------------
  # ----------------------------------------------------------------------------
  # ----------------------------------------------------------------------------
  # Let's try to make it fully generic!

  # create the empty form for USERS
  # USERS
  # USERS
  # USERS
  # USERS
  # USERS
  # USERS
  # USERS
  # USERS
  get '/cbgp/dataset/user-database/:form' do
    @form = params[:form]
    @database = get_dbname_for_form(form: @form)
    @mode = 'edit'
    @questionnaire = generate_questionnaire(questionnaire_type: @form) # questionnaire has all fields and possible answers
    @entry = CBGP::Dataset.new(type: @database) # the object into which the data will be inserted (may have more fields than the form!)
    halt erb :user_dataset, layout: :database_layout
  end

  # the form has been filled - now validate it
  post '/cbgp/validate-user-dataset/:database' do
    @form = params[:database]
    @questionnaire = generate_questionnaire(questionnaire_type: @form) # create the fields that will carry the answers provided
    @mode = 'edit' # the HTML form has a query mode and an edit mode.  Select the edit mode
    @entry = CBGP::Dataset.load_from_params_and_write(params: params)
    halt erb :thankyou, layout: :database_layout
  end

  # # POST route: lookup by identifier submitted in form body
  # post '/cbgp/dataset/user-database/:database' do
  #   load_dataset_for_edit(database: params[:database], primary_id: params[:primary_id]) # look to helpers
  # end

  # ADMINSTRATORS
  # ADMINSTRATORS
  # ADMINSTRATORS
  # ADMINSTRATORS
  # ADMINSTRATORS
  # ADMINSTRATORS
  # ADMINSTRATORS
  # create the empty form for ADMINSTRATORS
  get '/cbgp/dataset/:database' do
    @form = params[:database]
    @database = get_dbname_for_form(form: @form)
    @mode = 'edit'
    @questionnaire = generate_questionnaire(questionnaire_type: @database) # questionnaire has all fields and possible answers
    @entry = CBGP::Dataset.new(type: @database) # the object into which the data will be inserted
    halt erb :dataset, layout: :database_layout
  end

  # POST route: lookup by identifier submitted in form body
  post '/cbgp/dataset/:database' do
    load_dataset_for_edit(database: params[:database], primary_id: params[:primary_id]) # look to helpers
  end

  # GET route: direct access by primary_id (UUID) in URL – perfect for links from search results
  get '/cbgp/dataset/:database/:primary_id' do
    load_dataset_for_edit(database: params[:database], primary_id: params[:primary_id]) # look to helpers
  end

  # the form has been filled - now validate it
  post '/cbgp/validate-dataset/:database' do
    @form = params[:database]
    @database = get_dbname_for_form(form: @form)
    @questionnaire = generate_questionnaire(questionnaire_type: @form) # create the fields that will carry the answers provided
    @mode = 'edit' # the HTML form has a query mode and an edit mode.  Select the edit mode
    @entry = CBGP::Dataset.load_from_params_and_write(params: params)
    halt erb :dataset, layout: :database_layout
  end

  # LOADERS
  # LOADERS
  # LOADERS
  # LOADERS
  # LOADERS
  # LOADERS
  # LOADERS
  # LOADERS
  # LOADERS
  # LOADERS
  # LOADERS
  # LOADERS
  # LOADERS
  # LOADERS

  # GET route: direct access by primary_id (UUID) in URL – perfect for links from search results
  post '/cbgp/loaders' do
    type = params['loader']
    halt erb :doi_loader, layout: :database_layout if type.to_s == 'DOI'
  end

  post '/cbgp/loaders/load' do # this routine presumes it is always a DOI
    warn 'loading publication'
    doi = params['doi'] # this routine presumes it is always a DOI
    @database = params['database'] || 'publication'
    warn "database type #{@database}"
    @entry = CBGP::Loaders.load_doi(doi: doi)
    @questionnaire = generate_questionnaire(questionnaire_type: @database) # create the fields that will carry the answers provided
    @mode = 'edit' # the HTML form has a query mode and an edit mode.  Select the edit mode
    halt erb :dataset, layout: :database_layout
  end

  #
  # QUERY FORMS
  # QUERY FORMS
  # QUERY FORMS
  # QUERY FORMS
  # QUERY FORMS
  # QUERY FORMS
  # QUERY FORMS
  # QUERY FORMS
  # QUERY FORMS
  # QUERY FORMS
  # QUERY FORMS
  # QUERY FORMS
  # QUERY FORMS
  # QUERY FORMS

  # Ensure the full route context is included
  get '/cbgp/search-dataset/:database' do
    @database = params[:database]
    @questionnaire = generate_questionnaire(questionnaire_type: @database)
    @entry = CBGP::Dataset.new(type: @database)
    @mode = 'search'
    halt erb :search_dataset_inputform, layout: :database_layout
  end

  get '/cbgp/search-dataset' do # creates the search page iwth database in the POST body
    @database = params[:database]
    halt 400, 'Database parameter is required' unless @database
    @questionnaire = generate_questionnaire(questionnaire_type: @database)
    @entry = CBGP::Dataset.new(type: @database)
    @mode = 'search'
    halt erb :search_dataset_inputform, layout: :database_layout
  end

  post '/cbgp/query-dataset/:database' do # genereates the results page
    @database = params[:database]
    @questionnaire = generate_questionnaire(questionnaire_type: @database)
    @fields = CBGP::Dataset.get_questionnaire_fields(questionnaire_type: @database)

    search_params = params.reject { |k, _| k == 'database' }
    # warn "Search params: #{search_params.inspect}"
    graphuris = execute_search(search_params: search_params, dataset_type: @database) # returns strings
    # warn "Graph URIs: #{graphuris.inspect}"
    # warn "Fields: #{@fields.inspect}"
    @datasets = []
    graphuris.each do |graphuri| # these are sparql results!
      warn "LOADING Graph URI: #{graphuri}"
      @datasets << CBGP::Dataset.load_from_graph(graph: graphuri, database: @database)
    end
    # warn "Dataset details for rendering: #{@datasets.inspect}"
    erb :search_dataset_resultform, layout: :database_layout
  end

  ####################################################
  ################# LOADERS
  #
  post '/cbgp/publications/bulk' do
    dois = params[:dois]
    #    begin
    @messages = (CBGP::Publication.bulk_load_from_dois(dois: dois) if dois)

    halt erb :bulkpubs
  end

  get '/cbgp/publications/bulk' do
    halt erb :bulkpubs
  end

  ################# HELPERS
  #
  ## Merged handling for loading existing datasets (both by direct primary_id via GET and by identifier via POST)
  # The core logic is extracted into a helper method for full DRY compliance.
  # Both routes now delegate to the same code path.
  # - POST remains for form-based lookup (e.g., entering a DOI or other identifier)
  # - GET remains for direct linkability from search results (using the internal primary_id UUID)
  # The helper automatically detects special identifier types (e.g., DOI for publications) and routes accordingly.

  helpers do
    def load_dataset_for_edit(database:, primary_id:)
      halt 400, 'primary Identifier required' if primary_id.to_s.strip.empty?

      @database = database
      @mode = 'edit'
      @questionnaire = generate_questionnaire(questionnaire_type: @database)

      # Detect if the identifier is a special type (e.g., DOI) and clean it
      # If identifier_type returns nil/nothing special, fall back to the raw identifier
      idtype, clean_identifier = identifier_type(id: primary_id)
      clean_identifier ||= identifier

      # if @database == 'publication'
      #   if idtype == 'doi'
      #     @entry = CBGP::Publication.load_from_doi(doi: clean_identifier)
      #   else
      #     abort 'not allowed to load a dataset without a DOI but this should be changed!'
      #     # Fallback for publication primary_id (UUID) lookup
      #     # TODO: If Publication supports loading by primary_id, use it here.
      #     # For now, create new (or implement Publication.load_from_primary_id if needed)
      #     # @entry = CBGP::Publication.new
      #     # Optional future: @entry = CBGP::Publication.load_from_primary_id(primary_id: clean_identifier)
      #   end
      #   erb :publications, layout: :database_layout
      # else
      # Standard datasets: always load by identifier (primary_id or equivalent)
      @entry = CBGP::Dataset.load_from_primary_id(database: database, primary_id: clean_identifier)
      erb :dataset, layout: :database_layout
      # end
    end
  end
end
