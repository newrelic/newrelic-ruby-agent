# This is the initialization for the RPM Rails plugin
require 'new_relic/config'

# If you are having problems seeing data, be sure and check the
# newrelic_agent log files. 
# 
# If you can't find any log files and you don't see anything in your
# application log files, try uncommenting the following line to verify
# the plugin is being loaded, then contact support@newrelic.com 
# if you are unable to resolve the issue.

# ::RAILS_DEFAULT_LOGGER.warn "RPM detected environment: #{NewRelic::Config.instance.local_env}, RAILS_ENV: #{RAILS_ENV}"

# Initializer for the NewRelic Agent

begin
  # JRuby's glassfish plugin is trying to run the Initializer twice,
  # which isn't a good thing so we ignore subsequent invocations here.
  if ! defined?(::NEWRELIC_STARTED)
    ::NEWRELIC_STARTED = "#{caller.join("\n")}"
    NewRelic::Config.instance.start_plugin (defined?(config) ? config : nil)
  else
    NewRelic::Config.instance.log.debug "Attempt to initialize the plugin twice!"
    NewRelic::Config.instance.log.debug "Original call: \n#{::NEWRELIC_STARTED}"
    NewRelic::Config.instance.log.debug "Here we are now: \n#{caller.join("\n")}"
  end
rescue => e
  NewRelic::Config.instance.log! "Error initializing New Relic plugin (#{e})", :error
  NewRelic::Config.instance.log!  e.backtrace.join("\n"), :error
  NewRelic::Config.instance.log! "Agent is disabled."
end
