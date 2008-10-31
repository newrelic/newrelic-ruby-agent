# This is the initialization for the RPM Rails plugin
##require 'new_relic/config'

# Initializer for the NewRelic Agent
begin
  
  # START THE AGENT
  # We install the shim agent unless the tracers are enabled, the plugin
  # env setting is not false, and the agent started okay. 
  NewRelic::Config.instance.start_plugin (defined?(config) ? config : nil)

rescue => e
  NewRelic::Config.instance.log! "Error initializing New Relic plugin (#{e})", :error
  NewRelic::Config.instance.log!  e.backtrace.join("\n"), :error
  NewRelic::Config.instance.log! "Agent is disabled."
end
