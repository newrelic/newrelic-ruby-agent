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
      EXECUTION_ENVIRONMENT = "AWS_Lambda_ruby#{RUBY_VERSION.rpartition('.').first}".freeze
      LAMBDA_MARKER = 'NR_LAMBDA_MONITORING'
      LAMBDA_ENVIRONMENT_VARIABLE = 'AWS_LAMBDA_FUNCTION_NAME'
      METADATA_VERSION = 2 # internal to New Relic's cross-agent specs
      METHOD_BLOCKLIST = %i[connect preconnect shutdown profile_data get_agent_commands agent_command_results]
      NAMED_PIPE = '/tmp/newrelic-telemetry'
      SUPPORTABILITY_METRIC = 'Supportability/AWSLambda/HandlerInvocation'
      FUNCTION_NAME = 'lambda_function'
      VERSION = 1 # internal to New Relic's cross-agent specs

      def invoke_lambda_function_with_new_relic(hash = {})
        NewRelic::Agent.increment_metric(SUPPORTABILITY_METRIC)

        parse_context(hash[:context])

        NewRelic::Agent::Tracer.in_transaction(category: :other, name: function_name) do
          notice_cold_start
          send(hash[:method_name], hash[:event], hash[:context])
        end
      end

      def write(method, payload)
        return if METHOD_BLOCKLIST.include?(method)

        json = NewRelic::Agent.agent.service.marshaller.dump(payload)
        gzipped = NewRelic::Agent::NewRelicService::Encoders::Compressed::Gzip.encode(json)
        base64_encoded = NewRelic::Base64.encode64(gzipped)

        array = [VERSION, LAMBDA_MARKER, metadata, base64_encoded]

        write_output(::JSON.dump(array))
      end

      private

      def metadata
        {arn: @function_arn,
         protocol_version: NewRelic::Agent::NewRelicService::PROTOCOL_VERSION,
         function_version: @function_version,
         execution_environment: EXECUTION_ENVIRONMENT,
         agent_version: NewRelic::VERSION::STRING,
         metadata_version: METADATA_VERSION,
         agent_language: LANGUAGE}.reject { |_k, v| v.nil? }
      end

      def parse_context(context)
        @function_arn = nil
        @function_version = nil
        return unless context
        return unless context.respond_to?(:function_arn) && context.respond_to?(:function_version)

        @function_arn = context.function_arn
        @function_version = context.function_version
      end

      def function_name
        ENV.fetch(LAMBDA_ENVIRONMENT_VARIABLE, FUNCTION_NAME)
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
        return unless cold? && NewRelic::Agent::Tracer.current_transaction

        NewRelic::Agent::Tracer.current_transaction.add_agent_attribute(COLD_START_ATTRIBUTE,
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
