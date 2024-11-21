# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module DynamoDB
    INSTRUMENTED_METHODS = %w[
      create_table
      delete_item
      delete_table
      get_item
      put_item
      query
      scan
      update_item
    ].freeze

    PRODUCT = 'DynamoDB'
    DEFAULT_HOST = 'dynamodb.amazonaws.com'

    def instrument_method_with_new_relic(method_name, *args)
      return yield unless NewRelic::Agent::Tracer.tracing_enabled?

      NewRelic::Agent.record_instrumentation_invocation(PRODUCT)

      segment = NewRelic::Agent::Tracer.start_datastore_segment(
        product: PRODUCT,
        operation: method_name,
        host: config&.endpoint&.host || DEFAULT_HOST,
        port_path_or_id: config&.endpoint&.port,
        collection: args[0][:table_name]
      )

      arn = get_arn(args[0])
      segment&.add_agent_attribute('cloud.resource_id', arn) if arn

      @nr_captured_request = nil # clear request just in case
      begin
        NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
      ensure
        segment&.add_agent_attribute('aws.operation', method_name)
        segment&.add_agent_attribute('aws.requestId', @nr_captured_request&.context&.http_response&.headers&.[]('x-amzn-requestid'))
        segment&.add_agent_attribute('aws.region', config&.region)
        segment&.finish
      end
    end

    def build_request_with_new_relic(*args)
      @nr_captured_request = yield
    end

    def nr_account_id
      return @nr_account_id if defined?(@nr_account_id)

      @nr_account_id = NewRelic::Agent::Aws.get_account_id(config)
    end

    def get_arn(params)
      return unless params[:table_name]

      NewRelic::Agent::Aws.create_arn(PRODUCT.downcase, "table/#{params[:table_name]}", config&.region, nr_account_id)
    end
  end
end
