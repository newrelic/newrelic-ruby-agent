# Initialization script for the gem.
# Add 
#    #require 'new_relic'
# to your initialization sequence, as late as possible.
#
require 'new_relic/config'

def log!(message)
  STDERR.puts "[NewRelic] #{message}"
end

# START THE AGENT
# We install the shim agent unless the tracers are enabled, the plugin
# env setting is not false, and the agent started okay.
if !NewRelic::Config.instance.tracers_enabled?
  require 'new_relic/shim_agent'
else
  newrelic_config.start_plugin
end
