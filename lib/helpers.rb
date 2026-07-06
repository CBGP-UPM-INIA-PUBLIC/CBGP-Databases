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

  def _send_notification(subject:, message:)
    Pony.mail({
                to: NOTIFY_TO,
                from: NOTIFY_FROM,
                subject: subject,
                body: message,
                via: :smtp,
                via_options: {
                  address: NOTIFY_SMTP_ADDRESS,
                  port: NOTIFY_SMTP_PORT,
                  enable_starttls_auto: NOTIFY_SMTP_STARTTLS,
                  user_name: NOTIFY_UN,
                  password: NOTIFY_PW,
                  authentication: NOTIFY_SMTP_AUTH
                }
              })
  end

  # Emails the admin address (NOTIFY_TO) whenever a general User submits any
  # record through a UserFacing form (e.g. applying for a Project today;
  # registering incoming Staff is planned to reuse this too), so staff get a
  # heads-up before the User side is otherwise acted upon.
  #
  # Deliberately form-agnostic: rather than hardcoding which fields matter
  # (e.g. Title/Application reference for a project), it walks +dataset.fields+
  # — the same ontology-driven field list the form itself was built from —
  # and includes every field that actually has a value. Since a User-facing
  # form only ever populates its own restricted subset of a dataset type's
  # fields (see +user-project-fields+ etc. in the ontology), the email
  # naturally ends up containing exactly what the User submitted, whatever
  # form type that was, with no per-form code changes needed here.
  #
  # Best-effort: SMTP problems are logged via +warn+ and swallowed so a mail
  # outage never blocks the User's submission (the record is already saved by
  # the time this is called).
  #
  # @param dataset [CBGP::Dataset] the newly-written dataset
  # @param link [String, nil] direct URL to open the record in the admin interface
  def notify_new_user_submission(dataset:, link: nil)
    subject = "[CBGP] New #{dataset.form_type} submitted by a User"
    body = submission_notification_body(dataset: dataset, link: link)
    _send_notification(subject: subject, message: body)
  rescue StandardError => e
    warn "[NOTIFY] Failed to send new-#{dataset.form_type}-submission email: #{e.class}: #{e.message}"
  end

  private

  # Builds the email body: whatever fields the User actually filled in,
  # labeled as they appear on the form, plus identifying/tracking info.
  def submission_notification_body(dataset:, link:)
    lines = ["A new #{dataset.form_type} record has been submitted through the User portal.", '']
    lines.concat(submission_field_lines(dataset))
    lines << ''
    lines << "Primary ID: #{dataset.primary_id}"
    lines << "Submitted:  #{Time.now}"
    lines << '' << "Open this record: #{link}" if link
    lines.join("\n")
  end

  # One "Label: value" line per populated field, skipping fields the User
  # left blank (a UserFacing form only ever fills its own restricted subset
  # of the dataset type's fields).
  def submission_field_lines(dataset)
    dataset.fields.filter_map do |field|
      next unless field[:method]

      value = dataset.public_send(field[:method])
      next if value.nil? || (value.respond_to?(:empty?) && value.empty?)

      display = value.is_a?(Array) ? value.join(', ') : value.to_s
      format('%<label>-30s %<value>s', label: "#{field[:label]}:", value: display)
    end
  end
end
