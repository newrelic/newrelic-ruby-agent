# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module AwsSdkLambda
    INSTRUMENTATION_NAME = 'aws_sdk_lambda'
    AWS_SERVICE = 'lambda'
    CLOUD_PLATFORM = 'aws_lambda'
    ERROR_STATUS_REGEX = /^(?:4|5)/
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
        begin
          response = yield
          process_response(response, segment)
          response
        rescue => e
          # notice error that was unhandled by the AWS SDK Lambda client
          NewRelic::Agent.notice_error(e)
          raise
        end
      end
    ensure
      segment&.finish
    end

    def process_response(response, segment)
      process_status_code(response, segment) if response.respond_to?(:status_code)
      process_function_error(response.function_error, segment) if response.respond_to?(:function_error)
    end

    def process_status_code(response, segment)
      status_code = response.status_code
      return unless status_code

      segment.process_response_headers(WRAPPED_RESPONSE.new(status_code, true))

      # notice error that was handled by the function
      if status_code.to_s.match?(ERROR_STATUS_REGEX)
        payload = response.respond_to?(:payload) ? response.payload : '(empty response payload)'
        wrap_and_notice_error("Lambda function error handled with status #{status_code}: #{payload}")
      end
    end

    # notice error that was raised by the function
    def process_function_error(function_error, segment)
      return unless function_error

      wrap_and_notice_error(function_error)
    end

    def wrap_and_notice_error(msg)
      NewRelic::Agent.notice_error(StandardError.new(msg))
    end

    def generate_segment(action, options = {})
      function = function_name(options)
      region = aws_region
      account_id = aws_account_id
      arn = aws_arn(function, account_id, region)

      segment = NewRelic::Agent::Tracer.start_external_request_segment(
        library: INSTRUMENTATION_NAME,
        uri: "https://lambda.#{aws_region || 'unknown-region'}.amazonaws.com",
        procedure: action
      )
      segment.name = "External/Lambda/#{action}/#{function}"
      segment.add_agent_attribute('cloud.account.id', account_id)
      segment.add_agent_attribute('cloud.platform', CLOUD_PLATFORM)
      segment.add_agent_attribute('cloud.region', region)
      segment.add_agent_attribute('cloud.resource_id', arn) if arn

      segment
    end

    def function_name(options = {})
      (options.fetch(:function_name, nil) if options.respond_to?(:fetch)) || NewRelic::UNKNOWN
    end

    def aws_account_id
      return unless self.respond_to?(:config)

      configured_id = config&.account_id
      return configured_id if configured_id

      NewRelic::Agent::Aws.get_account_id(self.config)
    end

    def aws_region
      config&.region if self.respond_to?(:config)
    end

    def aws_arn(function, account_id, region)
      NewRelic::Agent::Aws.create_arn(AWS_SERVICE, "function:#{function}", region, account_id)
    end
  end
end
