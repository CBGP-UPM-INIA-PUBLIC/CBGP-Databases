require 'dotenv/load'

# Load .env file in development; in production, rely on Docker Compose env vars
Dotenv.load unless ENV['RACK_ENV'] == 'production'

# Set default values if not provided by .env or Docker Compose
ENV['VIRTUOSO_HOST'] ||= 'localhost:8890'

# Validate required environment variables
abort 'Missing NOTIFY_PW in environment variables or .env file' unless ENV['NOTIFY_PW']
abort 'Missing CBGP_USERS in environment variables or .env file' unless ENV['CBGP_USERS']
abort 'Missing CBGP_SECRET in environment variables or .env file' unless ENV['CBGP_SECRET']
abort 'Missing NOTIFY_TO in environment variables or .env file' unless ENV['NOTIFY_TO']
abort 'Missing NOTIFY_UN in environment variables or .env file' unless ENV['NOTIFY_UN']

# Parse and assign environment variables
USERS = JSON.parse(ENV.fetch('CBGP_USERS', nil))
CBGP_SECRET = ENV.fetch('CBGP_SECRET', nil)
# May be a single address or a comma-separated list (e.g. "a@x.org, b@x.org");
# Pony/the underlying mail gem accepts an Array for the :to field. Also strips
# stray quote characters per address, in case someone quotes each address
# individually (e.g. 'a@x.org','b@x.org') rather than the whole list.
NOTIFY_TO = ENV.fetch('NOTIFY_TO', nil).split(',').map { |addr| addr.strip.delete('\'"') }.reject(&:empty?)
NOTIFY_UN = ENV.fetch('NOTIFY_UN', nil)
NOTIFY_PW = ENV.fetch('NOTIFY_PW', nil)
# Outgoing mail account/server for admin notifications (e.g. new User
# submissions). Currently standing in with Mark's company mailer until the
# institute issues a dedicated account for this — swap via .env when it
# arrives, no code changes needed. Defaults below match that stand-in account.
NOTIFY_FROM = ENV.fetch('NOTIFY_FROM', 'mark.wilkinson@upm.es')
NOTIFY_SMTP_ADDRESS = ENV.fetch('NOTIFY_SMTP_ADDRESS', 'mail.fairdata.systems')
NOTIFY_SMTP_PORT = ENV.fetch('NOTIFY_SMTP_PORT', '587')
NOTIFY_SMTP_STARTTLS = ENV.fetch('NOTIFY_SMTP_STARTTLS', 'true') == 'true'
NOTIFY_SMTP_AUTH = ENV.fetch('NOTIFY_SMTP_AUTH', 'login') # :plain, :login, :cram_md5, or "none" for no auth
# Virtuoso, not GraphDB, as of 2026-08-25 (see CHANGELOG) - GraphDB's licensing
# requiring periodic re-registration even for the free tier was the trigger;
# Virtuoso Open Source has no such requirement.
#
# Unlike GraphDB, which hosts multiple named "repositories" inside one server
# process, a single Virtuoso process is one quad store. To keep the SCD Type
# 2 history store (see lib/queries.rb delete_dataset_query) *physically*
# separate from the current-state store - so current-state queries can never
# accidentally match a history graph, the same reasoning as before - this
# project runs two separate Virtuoso containers/processes, one per store,
# rather than one Virtuoso instance with the two separated by named graph
# alone. VIRTUOSO_HOST/VIRTUOSO_HISTORY_HOST are therefore two different
# host:port pairs, not a shared host with two dbnames.
VIRTUOSO_HOST = ENV.fetch('VIRTUOSO_HOST', nil)
VIRTUOSO_USER = ENV.fetch('VIRTUOSO_USER', nil)
VIRTUOSO_PASS = ENV.fetch('VIRTUOSO_PASS', nil)
VIRTUOSO_HISTORY_HOST = ENV.fetch('VIRTUOSO_HISTORY_HOST', nil)
HISTORY_USER = ENV.fetch('HISTORY_USER', VIRTUOSO_USER)
HISTORY_PASS = ENV.fetch('HISTORY_PASS', VIRTUOSO_PASS)
CBGP_KB = ENV.fetch('CBGP_KB', 'https://w3id.org/CBGP-App')
BASE_URI = 'http://admin.cbgp.upm.es/graphs/datasets/'

warn USERS
