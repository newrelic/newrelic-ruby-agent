# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Firehose
    INSTRUMENTED_METHODS = %w[
      create_delivery_stream
      delete_delivery_stream
      describe_delivery_stream
      list_delivery_streams
      list_tags_for_delivery_stream
      put_record
      put_record_batch
      start_delivery_stream_encryption
      stop_delivery_stream_encryption
      tag_delivery_stream
      untag_delivery_stream
      update_destination
    ].freeze

    FIREHOSE = 'Firehose'
    AWS_KINESIS_DELIVERY_STREAMS = 'aws_kinesis_delivery_streams'

    def instrument_method_with_new_relic(method_name, *args)
      return yield unless NewRelic::Agent::Tracer.tracing_enabled?

      NewRelic::Agent.record_instrumentation_invocation(FIREHOSE)

      params = args[0]
      segment = NewRelic::Agent::Tracer.start_segment(name: get_segment_name(method_name, params))
      arn = get_arn(params) if params
      segment&.add_agent_attribute('cloud.resource_id', arn) if arn

      begin
        NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
      ensure
        segment&.add_agent_attribute('cloud.platform', AWS_KINESIS_DELIVERY_STREAMS)
        segment&.finish
      end
    end

    def get_segment_name(method_name, params)
      return "#{FIREHOSE}/#{method_name}/#{params[:delivery_stream_name]}" if params&.dig(:delivery_stream_name)

      "#{FIREHOSE}/#{method_name}"
    rescue => e
      NewRelic::Agent.logger.warn("Failed to create segment name: #{e}")
    end

    def nr_account_id
      return @nr_account_id if defined?(@nr_account_id)

      @nr_account_id = NewRelic::Agent::Aws.get_account_id(config)
    end

    def get_arn(params)
      return params[:delivery_stream_arn] if params&.dig(:delivery_stream_arn)

      NewRelic::Agent::Aws.create_arn(FIREHOSE.downcase, "deliverystream/#{params[:delivery_stream_name]}", config&.region, nr_account_id) if params[:delivery_stream_name]
    end
  end
end
