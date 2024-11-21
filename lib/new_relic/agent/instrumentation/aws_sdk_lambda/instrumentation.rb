# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'json'

module NewRelic::Agent::Instrumentation
  module AwsSdkLambda
    INSTRUMENTATION_NAME = 'aws_sdk_lambda'
    AWS_SERVICE = 'lambda'
    CLOUD_PLATFORM = 'aws_lambda'
    WRAPPED_RESPONSE = Struct.new(:status_code, :has_status_code?)

    def invoke_with_new_relic(*args)
      with_tracing(:invoke, *args) { yield }
    end

    def invoke_async_with_new_relic(*args)
      with_tracing(:invoke_async, *args) { yield }
    end

    def invoke_with_response_stream_with_new_relic(*args)
      with_tracing(:invoke_with_response_stream, *args) { yield }
    end

    private

    def with_tracing(action, *args)
      segment = generate_segment(action, *args)

      # prevent additional instrumentation for things like Net::HTTP from
      # creating any segments that may appear as redundant / confusing
      NewRelic::Agent.disable_all_tracing do
        response = NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
        process_response(response, segment)
        response
      end
    ensure
      segment&.finish
    end

    def process_response(response, segment)
      process_function_error(response) if response.respond_to?(:function_error)
    rescue => e
      NewRelic::Agent.logger.error("Error processing aws-sdk-lambda invocation response: #{e}")
    end

    # notice error that was raised / unhandled by the function
    def process_function_error(response)
      function_error = response.function_error
      return unless function_error

      msg = "[#{function_error}]"
      payload = response.payload&.string if response.respond_to?(:payload)
      payload_hash = JSON.parse(payload) if payload
      msg = "#{msg} #{payload_hash['errorType']} - #{payload_hash['errorMessage']}" if payload_hash
      e = StandardError.new(msg)
      e.set_backtrace(payload_hash['stackTrace']) if payload_hash

      NewRelic::Agent.notice_error(e)
    end

    def generate_segment(action, options = {})
      function = function_name(options)
      region = aws_region
      arn = aws_arn(function, region)
      segment = NewRelic::Agent::Tracer.start_segment(name: "Lambda/#{action}/#{function}")
      segment.add_agent_attribute('cloud.account.id', nr_account_id)
      segment.add_agent_attribute('cloud.platform', CLOUD_PLATFORM)
      segment.add_agent_attribute('cloud.region', region)
      segment.add_agent_attribute('cloud.resource_id', arn) if arn
      segment
    end

    def function_name(options = {})
      (options.fetch(:function_name, nil) if options.respond_to?(:fetch)) || NewRelic::UNKNOWN
    end

    def aws_region
      config&.region if self.respond_to?(:config)
    end

    def aws_arn(function, region)
      NewRelic::Agent::Aws.create_arn(AWS_SERVICE, "function:#{function}", region, nr_account_id)
    end

    def nr_account_id
      return @nr_account_id if defined?(@nr_account_id)

      @nr_account_id = NewRelic::Agent::Aws.get_account_id(config)
    end
  end
end
