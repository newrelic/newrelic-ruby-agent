# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.


module NewRelic
  module Agent
    module Connect

      class RequestBuilder

        def initialize(new_relic_service, config)
          @service = new_relic_service
          @config = config
        end


        # Initializes the hash of settings that we send to the
        # server. Returns a literal hash containing the options
        def connect_payload
          {
            :pid           => $$,
            :host          => local_host,
            :display_host  => Agent.config[:'process_host.display_name'],
            :app_name      => Agent.config.app_names,
            :language      => 'ruby',
            :labels        => Agent.config.parsed_labels,
            :agent_version => NewRelic::VERSION::STRING,
            :environment   => sanitize_environment_report(environment_report),
            :settings      => Agent.config.to_collector_hash,
            :high_security => Agent.config[:high_security],
            :utilization   => UtilizationData.new.to_collector_hash,
            :identifier    => "ruby:#{local_host}:#{Agent.config.app_names.sort.join(',')}"
          }
        end

        # We've seen objects in the environment report (Rails.env in
        # particular) that can't seralize to JSON. Cope with that here and
        # clear out so downstream code doesn't have to check again.
        def sanitize_environment_report(environment_report)
          return [] unless @service.valid_to_marshal?(environment_report)
          environment_report
        end

        # Checks whether we should send environment info, and if so,
        # returns the snapshot from the local environment.
        # Generating the EnvironmentReport has the potential to trigger
        # require calls in Rails environments, so this method should only
        # be called synchronously from on the main thread.
        def environment_report
          Agent.config[:send_environment_info] ? Array(EnvironmentReport.new) : []
        end

        def local_host
          NewRelic::Agent::Hostname.get
        end
      end

      class ResponseHandler

        def initialize(new_relic_service)
          @service = new_relic_service
        end

        # Takes a hash of configuration data returned from the
        # server and uses it to set local variables and to
        # initialize various parts of the agent that are configured
        # separately.
        #
        # Can accommodate most arbitrary data - anything extra is
        # ignored unless we say to do something with it here.
        def finish_setup(config_data)
          return if config_data == nil

          @service.agent_id = config_data['agent_run_id']

          security_policies = config_data.delete('security_policies')

          add_server_side_config(config_data)
          add_security_policy_config(security_policies) if security_policies

          log_connection!(config_data)
          ::NewRelic::Agent.instance.transaction_rules = RulesEngine.create_transaction_rules(config_data)
          ::NewRelic::Agent.instance.stats_engine.metric_rules = RulesEngine.create_metric_rules(config_data)

          # If you're adding something else here to respond to the server-side config,
          # use Agent.instance.events.subscribe(:finished_configuring) callback instead!
        end

        def add_server_side_config(config_data)
          if config_data['agent_config']
            ::NewRelic::Agent.logger.debug "Using config from server"
          end

          ::NewRelic::Agent.logger.debug "Server provided config: #{config_data.inspect}"
          server_config = NewRelic::Agent::Configuration::ServerSource.new(config_data, Agent.config)
          ::NewRelic::Agent.config.replace_or_add_config(server_config)
        end

        def add_security_policy_config(security_policies)
          ::NewRelic::Agent.logger.info 'Installing security policies'
          security_policy_source = NewRelic::Agent::Configuration::SecurityPolicySource.new(security_policies)
          Agent.config.replace_or_add_config(security_policy_source)
          # drop data collected before applying security policies
          ::NewRelic::Agent.instance.drop_buffered_data
        end

        # Logs when we connect to the server, for debugging purposes
        # - makes sure we know if an agent has not connected
        def log_connection!(config_data)
          ::NewRelic::Agent.logger.debug "Connected to NewRelic Service at #{@service.collector.name}"
          ::NewRelic::Agent.logger.debug "Agent Run       = #{@service.agent_id}."
          ::NewRelic::Agent.logger.debug "Connection data = #{config_data.inspect}"
          if config_data['messages'] && config_data['messages'].any?
            log_collector_messages(config_data['messages'])
          end
        end

        def log_collector_messages(messages)
          messages.each do |message|
            ::NewRelic::Agent.logger.send(message['level'].downcase, message['message'])
          end
        end

      end
    end
  end
end
