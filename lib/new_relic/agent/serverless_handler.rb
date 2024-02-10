# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'json'
require 'new_relic/base64'

module NewRelic
  module Agent
    class ServerlessHandler
      VERSION = 1 # TODO
      METADATA_VERSION = 2 # TODO
      LAMBDA_MARKER = 'NR_LAMBDA_MONITORING'
      LAMBDA_ENVIRONMENT_VARIABLE = 'AWS_LAMBDA_FUNCTION_NAME'
      NAMED_PIPE = '/tmp/newrelic-telemetry'
      METHOD_BLOCKLIST = %i[connect preconnect shutdown profile_data get_agent_commands agent_command_results]

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
    end
  end
end

__END__

        # COLD_START_RECORDED is initialized to "False" when the container
        # first starts up, and will remain that way until the below lines
        # of code are encountered during the first transaction after the cold
        # start. We record this occurence on the transaction so that an
        # attribute is created, and then set COLD_START_RECORDED to False so
        # that the attribute is not created again during future invocations of
        # this container.

        global COLD_START_RECORDED
        if COLD_START_RECORDED is False:
            transaction._add_agent_attribute('aws.lambda.coldStart', True)
            COLD_START_RECORDED = True


