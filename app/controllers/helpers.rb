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

  def extract_date(value)
    if value.respond_to?(:to_s)
      value.to_s # Handle string or other objects with to_s
    else
      '' # Default to empty if no valid date
    end
  end
end
