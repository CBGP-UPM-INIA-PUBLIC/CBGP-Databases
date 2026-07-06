require 'dotenv/load'

# Load .env file in development; in production, rely on Docker Compose env vars
Dotenv.load unless ENV['RACK_ENV'] == 'production'

# Set default values if not provided by .env or Docker Compose
ENV['GRAPHDB_HOST'] ||= 'localhost:7200'

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
GRAPHDB_HOST = ENV.fetch('GRAPHDB_HOST', nil)
GRAPHDB_USER = ENV.fetch('GRAPHDB_USER', nil)
GRAPHDB_PASS = ENV.fetch('GRAPHDB_PASS', nil)
GRAPHDB_DBNAME = ENV.fetch('GRAPHDB_DBNAME', 'kbdatabase')
CBGP_KB = ENV.fetch('CBGP_KB', 'https://w3id.org/CBGP-App')
BASE_URI = 'http://admin.cbgp.upm.es/graphs/datasets/'

warn USERS
