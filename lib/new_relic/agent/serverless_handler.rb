# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'json'
require 'new_relic/base64'

module NewRelic
  module Agent
    class ServerlessHandler
      ATTRIBUTE_ARN = 'aws.lambda.arn'
      ATTRIBUTE_COLD_START = 'aws.lambda.coldStart'
      ATTRIBUTE_REQUEST_ID = 'aws.requestId'
      AGENT_ATTRIBUTE_DESTINATIONS = NewRelic::Agent::AttributeFilter::DST_TRANSACTION_TRACER |
        NewRelic::Agent::AttributeFilter::DST_TRANSACTION_EVENTS
      EXECUTION_ENVIRONMENT = "AWS_Lambda_ruby#{RUBY_VERSION.rpartition('.').first}".freeze
      LAMBDA_MARKER = 'NR_LAMBDA_MONITORING'
      LAMBDA_ENVIRONMENT_VARIABLE = 'AWS_LAMBDA_FUNCTION_NAME'
      METHOD_BLOCKLIST = %i[agent_command_results connect get_agent_commands log_event_data preconnect profile_data
        shutdown].freeze
      NAMED_PIPE = '/tmp/newrelic-telemetry'
      SUPPORTABILITY_METRIC = 'Supportability/AWSLambda/HandlerInvocation'
      FUNCTION_NAME = 'lambda_function'
      VERSION = 1 # internal to New Relic's cross-agent specs

      def self.env_var_set?
        ENV.key?(LAMBDA_ENVIRONMENT_VARIABLE)
      end

      def initialize
        @context = nil
        @payloads = {}
      end

      def invoke_lambda_function_with_new_relic(event:, context:, method_name:, namespace: nil)
        NewRelic::Agent.increment_metric(SUPPORTABILITY_METRIC)

        @context = context

        NewRelic::Agent::Tracer.in_transaction(category: :other, name: function_name) do
          add_agent_attributes

          NewRelic::LanguageSupport.constantize(namespace).send(method_name, event: event, context: context)
        end
      ensure
        harvest!
        write_output
        reset!
      end

      def store_payload(method, payload)
        return if METHOD_BLOCKLIST.include?(method)

        @payloads[method] = payload
      end

      private

      def harvest!
        NewRelic::Agent.instance.harvest_and_send_analytic_event_data
        NewRelic::Agent.instance.harvest_and_send_custom_event_data
        NewRelic::Agent.instance.harvest_and_send_data_types
      end

      def metadata
        {arn: @context.invoked_function_arn,
         protocol_version: NewRelic::Agent::NewRelicService::PROTOCOL_VERSION,
         function_version: @context.function_version,
         execution_environment: EXECUTION_ENVIRONMENT,
         agent_version: NewRelic::VERSION::STRING}
      end

      def function_name
        ENV.fetch(LAMBDA_ENVIRONMENT_VARIABLE, FUNCTION_NAME)
      end

      def write_output
        payload_hash = {'metadata' => metadata, 'data' => @payloads}
        json = NewRelic::Agent.agent.service.marshaller.dump(payload_hash)
        gzipped = NewRelic::Agent::NewRelicService::Encoders::Compressed::Gzip.encode(json)
        base64_encoded = NewRelic::Base64.encode64(gzipped)
        array = [VERSION, LAMBDA_MARKER, base64_encoded]
        string = ::JSON.dump(array)

        return puts string unless use_named_pipe?

        File.write(NAMED_PIPE, string)

        NewRelic::Agent.logger.debug "Wrote serverless payload to #{NAMED_PIPE}\n" \
          "BEGIN PAYLOAD>>>\n#{string}\n<<<END PAYLOAD"
      end

      def use_named_pipe?
        return @use_named_pipe if defined?(@use_named_pipe)

        @use_named_pipe = File.exist?(NAMED_PIPE) && File.writable?(NAMED_PIPE)
      end

      def add_agent_attributes
        return unless NewRelic::Agent::Tracer.current_transaction

        add_agent_attribute(ATTRIBUTE_COLD_START, true) if cold?
        add_agent_attribute(ATTRIBUTE_ARN, @context.invoked_function_arn)
        add_agent_attribute(ATTRIBUTE_REQUEST_ID, @context.aws_request_id)
      end

      def add_agent_attribute(attribute, value)
        NewRelic::Agent::Tracer.current_transaction.add_agent_attribute(attribute, value, AGENT_ATTRIBUTE_DESTINATIONS)
      end

      def cold?
        return @cold if defined?(@cold)

        @cold = false
        true
      end

      def reset!
        @context = nil
        @payloads.replace({})
      end
    end
  end
end
