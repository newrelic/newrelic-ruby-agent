$:.unshift "../Agent"
$:.unshift "../Common"

require 'yaml'

config_file = File.read(RAILS_ROOT+"/config/seldon.yml")
agent_config = YAML.load(config_file)[RAILS_ENV]

require 'seldon/agent'

if agent_config[:enabled]
  Seldon::Agent.instance.start(agent_config)
end
