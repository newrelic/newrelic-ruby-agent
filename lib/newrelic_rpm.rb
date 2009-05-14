# = New Relic Agent
#
# This file is the initialization script for the gem.  The agent can also be started
# as a plugin.
#
# == Starting the Agent
#
# For Rails, add:
#    config.gem 'newrelic_rpm'
# to your initialization sequence.
#
# For merb, do 
#    dependency 'newrelic_rpm'
# in the Merb config/init.rb
#
# For other frameworks, or to manage the agent manually, invoke NewRelic::Agent#manual_start
# directly.
#
# == Configuring the Agent
# 
# All agent configuration is done in the <code>newrelic.yml</code> file.  This file is by
# default read from the +config+ directory of the application root and is subsequently
# searched for in the application root directory, and then in a <code>~/.newrelic</code> directory
#
# == Agent APIs
#
# The agent has some APIs available for extending and customizing.
# :main: 
require 'new_relic/control'

def log!(message)
  STDERR.puts "[NewRelic] #{message}"
end

# After verison 2.0 of Rails we can access the configuration directly.
# We need it to add dev mode routes after initialization finished. 
if defined? Rails.configuration
  Rails.configuration.after_initialize do
    NewRelic::Control.instance.init_plugin :config => Rails.configuration
  end
else
  NewRelic::Control.instance.init_plugin
end
