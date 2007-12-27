require 'yaml'
require 'seldon/agent'

# Initializer for the Seldon Agent
seldon_config_file = File.read(RAILS_ROOT+"/config/seldon.yml")
seldon_agent_config = YAML.load(seldon_config_file)[RAILS_ENV]
seldon_agent_config.freeze

::SELDON_AGENT_ENABLED = seldon_agent_config['enabled']
::SELDON_DEVELOPER = seldon_agent_config['enabled'] && seldon_agent_config['developer']

if ::SELDON_AGENT_ENABLED
  require 'seldon/agent/instrument_rails'
  
  ::SELDON_HOST = seldon_agent_config['host']
  ::SELDON_PORT = seldon_agent_config['port']
  
  puts "HOST: #{::SELDON_HOST}"
  Seldon::Agent.instance.start(seldon_agent_config)
  
  if ::SELDON_DEVELOPER
    controller_path = File.join(File.dirname(__FILE__), 'ui', 'controllers')
    $LOAD_PATH << controller_path
    Dependencies.load_paths << controller_path
    config.controller_paths << controller_path
  end
end

