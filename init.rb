# This is the initialization for the RPM Rails plugin
##require 'new_relic/config'

# Initializer for the NewRelic Agent
# JRuby's glassfish plugin is trying to run the Initializer twice,
# which isn't a good thing so we ignore subsequent invocations here.
begin
  # START THE AGENT
  # We install the shim agent unless the tracers are enabled, the plugin
  # env setting is not false, and the agent started okay. 
  if ! defined?(::NEWRELIC_STARTED)
    ::NEWRELIC_STARTED = "#{caller.join("\n")}"
    NewRelic::Config.instance.start_plugin (defined?(config) ? config : nil)
  else
    NewRelic::Config.instance.log.debug "Attempt to initialize the plugin twice!"
    #NewRelic::Config.instance.log.debug "Original call: \n#{::NEWRELIC_STARTED}"
    #NewRelic::Config.instance.log.debug "Here we are now: \n#{caller.join("\n")}"
  end
rescue => e
  NewRelic::Config.instance.log! "Error initializing New Relic plugin (#{e})", :error
  NewRelic::Config.instance.log!  e.backtrace.join("\n"), :error
  NewRelic::Config.instance.log! "Agent is disabled."
end
