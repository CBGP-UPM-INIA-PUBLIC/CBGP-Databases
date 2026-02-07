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

  # helper
  def generate_questionnaire(questionnaire_type:)
    Questionnaire.get_cached(questionnaire_type: questionnaire_type) # OPTIMIZATION: Use cache instead of new()
  end

  def to_plain_hash(obj) # used to rerun seearches with the same parameters
    case obj
    when Hash
      obj.transform_values { |v| to_plain_hash(v) }
    when Array
      obj.map { |v| to_plain_hash(v) }
    else
      obj
    end
  end
end
