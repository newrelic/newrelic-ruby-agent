require 'yaml'
require 'newrelic/agent/method_tracer'

# Initializer for the NewRelic Agent
config_filename = File.join(File.dirname(__FILE__), '..','..','..','config','newrelic.yml')
begin
  newrelic_config_file = File.read(config_filename)

  newrelic_agent_config = YAML.load(newrelic_config_file)[RAILS_ENV]
  newrelic_agent_config.freeze

  ::RPM_AGENT_ENABLED = newrelic_agent_config['enabled']
  ::RPM_DEVELOPER = newrelic_agent_config['developer']

  ::RPM_TRACERS_ENABLED = ::RPM_DEVELOPER || ::RPM_AGENT_ENABLED
  
  # note if the agent is not turned on via the enabled flag in the 
  # configuration file, the application will be untouched, and it will
  # behave exaclty as if the agent were never installed in the first place.
  if ::RPM_AGENT_ENABLED || ::RPM_DEVELOPER
    require 'newrelic/agent'
  
    NewRelic::Agent.instance.start(newrelic_agent_config)
  
    if ::RPM_DEVELOPER
      controller_path = File.join(File.dirname(__FILE__), 'ui', 'controllers')
      helper_path = File.join(File.dirname(__FILE__), 'ui', 'helpers')
      $LOAD_PATH << controller_path
      $LOAD_PATH << helper_path
      Dependencies.load_paths << controller_path
      Dependencies.load_paths << helper_path
      config.controller_paths << controller_path
    end
  end
rescue Errno::ENOENT => e
  STDERR.puts "** [NewRelic] could not find configuration file #{config_filename}."
  STDERR.puts "** [NewRelic] be sure to put newrelic.yml into your config directory."
  STDERR.puts "** [NewRelic] Agent is disabled."
rescue Exception => e
  STDERR.puts "** [NewRelic] Error parsing #{config_filename}"
  STDERR.puts "** [NewRelic] #{e}"
  STDERR.puts "** [NewRelic] Agent is disabled."
end
