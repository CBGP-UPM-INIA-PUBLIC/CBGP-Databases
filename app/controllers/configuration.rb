ENV['CBGP_USERS'] = '{"markw": "markw"}'
ENV['NOTIFY_TO'] ='mark.wilkinson@upm.es'
ENV['NOTIFY_PW'] =''
ENV['NOTIFY_UN'] ='mark.wilkinson'
ENV['CBGP_SECRET'] ='dUS3a8sTGgrwZ97kjuxUeKTTzPBG9tj5mwGtwgexEupuXmjw2BQPMJ8jaun32BwQAEh2GWKB6V5W6bZL4FbgL2v5FwyGwbZsA48EfFHqKVvPYrcZBFdVSDM4jEhP9NBY'


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

warn USERS
