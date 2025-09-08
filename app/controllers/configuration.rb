ENV['CBGP_USERS'] = '{"markw": "markw"}'
ENV['NOTIFY_TO'] ='mark.wilkinson@upm.es'
ENV['NOTIFY_PW'] =''
ENV['NOTIFY_UN'] ='mark.wilkinson'
ENV['CBGP_SECRET'] ='dUS3a8sTGgrwZ97kjuxUeKTTzPBG9tj5mwGtwgexEupuXmjw2BQPMJ8jaun32BwQAEh2GWKB6V5W6bZL4FbgL2v5FwyGwbZsA48EfFHqKVvPYrcZBFdVSDM4jEhP9NBY'
ENV["GRAPHDB_HOST"] ||= "localhost:7200"  # could already be set by docker compose
ENV["CBGP_KB"] ||= "./cbgp-application-form/ontology_all.owl"  # could already be set by docker compose
ENV["GRAPHDB_USER"] ||= "cbgp" # could already be set by docker compose
ENV["GRAPHDB_PASS"] ||= "cbgp" # could already be set by docker compose

abort "you didn't set an email password NOTIFY_PW" unless ENV["NOTIFY_PW"]
abort "you didn't set usernames passwords in CBGP_USERS" unless ENV["CBGP_USERS"]
abort "you didn't set CBGP_SECRET" unless ENV["CBGP_SECRET"]
abort "you didn't set NOTIFY_TO" unless ENV["NOTIFY_TO"]
abort "you didn't set NOTIFY_UN" unless ENV["NOTIFY_UN"]

USERS = JSON.parse(ENV['CBGP_USERS'])
CBGP_SECRET = ENV['CBGP_SECRET']
NOTIFY_TO = ENV["NOTIFY_TO"]
NOTIFY_UN = ENV["NOTIFY_UN"]
NOTIFY_PW = ENV["NOTIFY_PW"]
GRAPHDB_HOST = ENV["GRAPHDB_HOST"] 
GRAPHDB_USER = ENV["GRAPHDB_USER"] 
GRAPHDB_PASS = ENV["GRAPHDB_PASS"] 
CBGP_KB = ENV["CBGP_KB"] 

warn USERS
