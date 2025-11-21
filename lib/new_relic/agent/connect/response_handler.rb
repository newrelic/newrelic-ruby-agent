# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Connect
      class ResponseHandler
        def initialize(agent, config)
          @agent = agent
          @config = config
        end

        # Takes a hash of configuration data returned from the
        # server and uses it to set local variables and to
        # initialize various parts of the agent that are configured
        # separately.
        #
        # Can accommodate most arbitrary data - anything extra is
        # ignored unless we say to do something with it here.
        def configure_agent(config_data)
          return if config_data.nil?

          @agent.agent_id = config_data['agent_run_id']

          add_server_side_config(config_data)

          @agent.transaction_rules = RulesEngine.create_transaction_rules(config_data)
          @agent.stats_engine.metric_rules = RulesEngine.create_metric_rules(config_data)

          # If you're adding something else here to respond to the server-side config,
          # use Agent.instance.events.subscribe(:initial_configuration_complete) callback instead!
        end

        def add_server_side_config(config_data)
          if config_data['agent_config']
            ::NewRelic::Agent.logger.debug('Using config from server')
          end

          ::NewRelic::Agent.logger.debug("Server provided config: #{config_data.inspect}")
          server_config = NewRelic::Agent::Configuration::ServerSource.new(config_data, @config)
          @config.replace_or_add_config(server_config)
        end
      end
    end
  end
end
