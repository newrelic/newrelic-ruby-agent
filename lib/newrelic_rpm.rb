# Initialization script for the gem.
# Add 
#    config.gem 'newrelic_rpm'
# to your initialization sequence.
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
  # After verison 2.0 of Rails we can access the configuration directly.
  # We need it to add dev mode routes after initialization finished. 
  if defined? Rails.configuration
    Rails.configuration.after_initialize do
      NewRelic::Config.instance.start_plugin Rails.configuration
    end
  else
    NewRelic::Config.instance.start_plugin
  end
end
