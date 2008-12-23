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
  # if we are in the rails initializer, pass the config into the plugin
  # so we can set up dev mode
  if defined? config
    c = [ config ]
  else
    c = []
  end
  NewRelic::Config.instance.start_plugin *c
end
