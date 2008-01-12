require 'yaml'
require 'newrelic/agent'

# Initializer for the NewRelic Agent
newrelic_config_file = File.read(RAILS_ROOT+"/config/newrelic.yml")
newrelic_agent_config = YAML.load(newrelic_config_file)[RAILS_ENV]
newrelic_agent_config.freeze

::SELDON_AGENT_ENABLED = newrelic_agent_config['enabled']
::SELDON_DEVELOPER = newrelic_agent_config['enabled'] && newrelic_agent_config['developer']

if ::SELDON_AGENT_ENABLED
  require 'newrelic/agent/instrument_rails'
  
  ::SELDON_HOST = newrelic_agent_config['host']
  ::SELDON_PORT = newrelic_agent_config['port']

  NewRelic::Agent.instance.start(newrelic_agent_config)
  
  if ::SELDON_DEVELOPER
    controller_path = File.join(File.dirname(__FILE__), 'ui', 'controllers')
    helper_path = File.join(File.dirname(__FILE__), 'ui', 'helpers')
    $LOAD_PATH << controller_path
    $LOAD_PATH << helper_path
    Dependencies.load_paths << controller_path
    Dependencies.load_paths << helper_path
    config.controller_paths << controller_path
  end
end

