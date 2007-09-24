require 'yaml'
require 'seldon/agent'

# Initializer for the Seldon Agent
config_file = File.read(RAILS_ROOT+"/config/seldon.yml")
agent_config = YAML.load(config_file)[RAILS_ENV]

::SELDON_AGENT_ENABLED = agent_config['enabled']
if agent_config['enabled']
  require 'seldon/agent/instrument_rails'
  
  Seldon::Agent.instance.start(agent_config)
end
