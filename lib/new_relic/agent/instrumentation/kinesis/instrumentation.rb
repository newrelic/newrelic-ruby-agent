# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# external_request segment?

module NewRelic::Agent::Instrumentation
  module Kinesis
    INSTRUMENTED_METHODS = %w[
      add_tags_to_stream
      create_stream
      decrease_stream_retention_period
      delete_stream
      describe_limits
      describe_stream
      disable_enhanced_monitoring
      enable_enhanced_monitoring
      get_records
      get_shard_iterator
      increase_stream_retention_period
      list_streams
      list_tags_for_stream
      merge_shards
      put_record
      put_records
      remove_tags_from_stream
      split_shard
      update_shard_count
    ].freeze

    KINESIS = 'Kinesis'
    AWS_KINESIS_DATA_STREAMS = 'aws_kinesis_data_streams'

    def instrument_method_with_new_relic(method_name, *args)
      return yield unless NewRelic::Agent::Tracer.tracing_enabled?

      NewRelic::Agent.record_instrumentation_invocation(KINESIS)
      
      params = args[0]
      segment = NewRelic::Agent::Tracer.start_segment(name: segment_name(method_name, params))
      arn = get_arn(params) if params
      segment&.add_agent_attribute('cloud.resource_id', arn) if arn

      begin
        NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
      ensure
        segment&.add_agent_attribute('cloud.platform', AWS_KINESIS_DATA_STREAMS)
        segment&.add_agent_attribute('name', segment_name(method_name, params))
        segment&.finish
      end
    end

    def segment_name(method_name, params)
      return "#{KINESIS}/#{method_name}/#{params[:stream_name]}" if params&.dig(:stream_name)

      "#{KINESIS}/#{method_name}"
    rescue => e
      NewRelic::Agent.logger.warn("Failed to create segment name: #{e}")
    end

    def get_arn(params)
      return params[:stream_arn] if params[:stream_arn]

      NewRelic::Agent::Aws.create_arn(KINESIS.downcase, "stream/#{params[:stream_name]}", config&.region) if params[:stream_name]
    end
  end
end
