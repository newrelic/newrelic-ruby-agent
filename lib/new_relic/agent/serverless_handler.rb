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
      METHOD_BLOCKLIST = %i[agent_command_results connect get_agent_commands preconnect profile_data
        shutdown].freeze
      NAMED_PIPE = '/tmp/newrelic-telemetry'
      SUPPORTABILITY_METRIC = 'Supportability/AWSLambda/HandlerInvocation'
      FUNCTION_NAME = 'lambda_function'
      PAYLOAD_VERSION = ENV.fetch('NEW_RELIC_SERVERLESS_PAYLOAD_VERSION', 2)

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

      def metric_data(stats_hash)
        payload = [nil,
          stats_hash.started_at,
          (stats_hash.harvested_at || Process.clock_gettime(Process::CLOCK_REALTIME)),
          []]
        stats_hash.each do |metric_spec, stats|
          next if stats.is_reset?

          hash = {name: metric_spec.name}
          hash[:scope] = metric_spec.scope unless metric_spec.scope.empty?

          payload.last.push([hash, [
            stats.call_count,
            stats.total_call_time,
            stats.total_exclusive_time,
            stats.min_call_time,
            stats.max_call_time,
            stats.sum_of_squares
          ]])
        end

        return if payload.last.empty?

        store_payload(:metric_data, payload)
      end

      def error_data(errors)
        store_payload(:error_data, [nil, errors.map(&:to_collector_array)])
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
        string = PAYLOAD_VERSION == 1 ? payload_v1 : payload_v2

        return puts string unless use_named_pipe?

        File.write(NAMED_PIPE, string)

        NewRelic::Agent.logger.debug "Wrote serverless payload to #{NAMED_PIPE}\n" \
          "BEGIN PAYLOAD>>>\n#{string}\n<<<END PAYLOAD"
      end

      def payload_v1
        payload_hash = {'metadata' => metadata, 'data' => @payloads}
        json = NewRelic::Agent.agent.service.marshaller.dump(payload_hash)
        gzipped = NewRelic::Agent::NewRelicService::Encoders::Compressed::Gzip.encode(json)
        base64_encoded = NewRelic::Base64.strict_encode64(gzipped)
        array = [PAYLOAD_VERSION, LAMBDA_MARKER, base64_encoded]
        ::JSON.dump(array)
      end

      def payload_v2
        json = NewRelic::Agent.agent.service.marshaller.dump(@payloads)
        gzipped = NewRelic::Agent::NewRelicService::Encoders::Compressed::Gzip.encode(json)
        base64_encoded = NewRelic::Base64.strict_encode64(gzipped)
        array = [PAYLOAD_VERSION, LAMBDA_MARKER, metadata, base64_encoded]
        ::JSON.dump(array)
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
