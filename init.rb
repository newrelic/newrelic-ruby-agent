require 'yaml'
require 'seldon/agent'

# Initializer for the Seldon Agent
config_file = File.read(RAILS_ROOT+"/config/seldon.yml")
agent_config = YAML.load(config_file)[RAILS_ENV]

::SELDON_AGENT_ENABLED = agent_config['enabled']
::SELDON_DEVELOPER = agent_config['enabled'] && agent_config['developer']

if ::SELDON_AGENT_ENABLED
  require 'seldon/agent/instrument_rails'
  
  Seldon::Agent.instance.start(agent_config)
  
  if SELDON_DEVELOPER
    controller_path = File.join(File.dirname(__FILE__), 'ui', 'controllers')
    $LOAD_PATH << controller_path
    Dependencies.load_paths << controller_path
    config.controller_paths << controller_path
  end
end

