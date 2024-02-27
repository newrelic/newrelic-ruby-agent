# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'json'
require 'new_relic/base64'

module NewRelic
  module Agent
    class ServerlessHandler
      COLD_START_ATTRIBUTE = 'aws.lambda.coldStart'
      COLD_START_DESTINATIONS = NewRelic::Agent::AttributeFilter::DST_TRANSACTION_TRACER |
        NewRelic::Agent::AttributeFilter::DST_TRANSACTION_EVENTS
      LAMBDA_MARKER = 'NR_LAMBDA_MONITORING'
      LAMBDA_ENVIRONMENT_VARIABLE = 'AWS_LAMBDA_FUNCTION_NAME'
      METADATA_VERSION = 2 # TODO
      METHOD_BLOCKLIST = %i[connect preconnect shutdown profile_data get_agent_commands agent_command_results]
      NAMED_PIPE = '/tmp/newrelic-telemetry'
      SUPPORTABILITY_METRIC = 'Supportability/AWSLambda/HandlerInvocation'
      TRANSACTION_NAME = 'lambda_function'
      VERSION = 1 # TODO

      def lambda_handler(hash = {})
        NewRelic::Agent.increment_metric(SUPPORTABILITY_METRIC)

        # TODO: category and name
        NewRelic::Agent::Tracer.in_transaction(category: :other, name: TRANSACTION_NAME) do
          notice_cold_start
          send(hash[:method_name], hash[:event], hash[:context])
        end
      end

      def write(method, payload)
        return if METHOD_BLOCKLIST.include?(method)

        metadata = {arn: 'AWS_LAMBDA_FUNCTION_ARN', # TODO
                    protocol_version: NewRelic::Agent::NewRelicService::PROTOCOL_VERSION,
                    function_version: '15', # TODO
                    execution_environment: 'AWS_Lambda_ruby3.2', # TODO
                    agent_version: NewRelic::VERSION::STRING,
                    metadata_version: METADATA_VERSION,
                    agent_language: LANGUAGE}

        json = NewRelic::Agent.agent.service.marshaller.dump(payload)
        gzipped = NewRelic::Agent::NewRelicService::Encoders::Compressed::Gzip.encode(json)
        base64_encoded = NewRelic::Base64.encode64(gzipped)

        array = [VERSION, LAMBDA_MARKER, metadata, base64_encoded]

        write_output(::JSON.dump(array))
      end

      def write_output(string)
        return puts string unless use_named_pipe?

        File.open(NAMED_PIPE, 'w') { |f| f.puts string }
      end

      def use_named_pipe?
        return @use_named_pipe if defined?(@use_named_pipe)

        @use_named_pipe = File.exist?(NAMED_PIPE) && File.writable?(NAMED_PIPE)
      end

      def notice_cold_start
        return unless cold?

        NewRelic::Agent::Tracer.current_transaction&.add_agent_attribute(COLD_START_ATTRIBUTE,
          true,
          COLD_START_DESTINATIONS)
      end

      def cold?
        return @cold if defined?(@cold)

        @cold = false
        true
      end
    end
  end
end
