
module MyHelpers
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