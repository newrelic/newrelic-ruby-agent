# Initialization script for the gem.
# The gem currently works with Rails 2.0 and up, and Merb 1.0 and up.
#
# For Rails, add:
#    config.gem 'newrelic_rpm'
# to your initialization sequence.
#
# For merb, do 
#    dependency 'newrelic_rpm'
# in the Merb config/init.rb
#
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
