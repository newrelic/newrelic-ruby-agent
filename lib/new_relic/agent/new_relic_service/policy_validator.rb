# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class NewRelicService
      class PolicyValidator
        EXPECTED_SECURITY_POLICIES = [
          "record_sql".freeze,
          "attributes_include".freeze,
          "allow_raw_exception_messages".freeze,
          "custom_events".freeze,
          "custom_parameters".freeze,
          "custom_instrumentation_editor".freeze,
          "message_parameters".freeze,
          "job_arguments".freeze]

        def initialize(preconnect_response)
          @preconnect_policies = preconnect_response['security_policies'] || {}
        end

        def validate_matching_agent_config!
          agent_keys = EXPECTED_SECURITY_POLICIES
          all_server_keys = @preconnect_policies.keys
          required_server_keys = @preconnect_policies.select do |key, value|
            value['required']
          end.keys

          missing_from_agent = required_server_keys - agent_keys
          unless missing_from_agent.empty?
            message = "The agent received one or more required security policies \
that it does not recognize and will shut down: #{missing_from_agent.join(',')}. \
Please check if a newer agent version supports these policies or contact support."
            raise NewRelic::Agent::UnrecoverableAgentException.new(message)
          end

          missing_from_server = agent_keys - all_server_keys
          unless missing_from_server.empty?
            message = "The agent did not receive one or more security policies \
that it expected and will shut down: #{missing_from_server.join(',')}. Please \
contact support."
            raise NewRelic::Agent::UnrecoverableAgentException.new(message)
          end
        end
      end
    end
  end
end
