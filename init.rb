require 'yaml'
require 'seldon/agent'

# Initializer for the Seldon Agent
config_file = File.read(RAILS_ROOT+"/config/seldon.yml")
agent_config = YAML.load(config_file)[RAILS_ENV]

p agent_config
puts "Enabled: #{agent_config['enabled']}"
if agent_config['enabled']
  Seldon::Agent.instance.start(agent_config)
end
