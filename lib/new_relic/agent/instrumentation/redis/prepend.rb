# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative 'redis_instrumentation'

module NewRelic::Agent::Instrumentation
  module Redis
    module Prepend

      def call(*args, &block)
        operation = args[0][0]
        statement = ::NewRelic::Agent::Datastores::Redis.format_command(args[0])

        hostname = NewRelic::Agent::Instrumentation::Redis.host_for(self)
        port_path_or_id = NewRelic::Agent::Instrumentation::Redis.port_path_or_id_for(self)

        segment = NewRelic::Agent::Tracer.start_datastore_segment(
          product: NewRelic::Agent::Datastores::Redis::PRODUCT_NAME,
          operation: operation,
          host: hostname,
          port_path_or_id: port_path_or_id,
          database_name: db
        )
        begin
          segment.notice_nosql_statement(statement) if statement
          NewRelic::Agent::Tracer.capture_segment_error segment do
            super
          end
        ensure
          segment.finish if segment
        end
      end

      def call_pipeline(*args, &block)
        pipeline = args[0]
        operation = pipeline.is_a?(::Redis::Pipeline::Multi) ? NewRelic::Agent::Datastores::Redis::MULTI_OPERATION : NewRelic::Agent::Datastores::Redis::PIPELINE_OPERATION
        statement = ::NewRelic::Agent::Datastores::Redis.format_pipeline_commands(pipeline.commands)

        hostname = NewRelic::Agent::Instrumentation::Redis.host_for(self)
        port_path_or_id = NewRelic::Agent::Instrumentation::Redis.port_path_or_id_for(self)

        segment = NewRelic::Agent::Tracer.start_datastore_segment(
          product: NewRelic::Agent::Datastores::Redis::PRODUCT_NAME,
          operation: operation,
          host: hostname,
          port_path_or_id: port_path_or_id,
          database_name: db
        )
        begin
          segment.notice_nosql_statement(statement)
          NewRelic::Agent::Tracer.capture_segment_error segment do
            super
          end
        ensure
          segment.finish if segment
        end
      end

      def connect(*args, &block)
        hostname = NewRelic::Agent::Instrumentation::Redis.host_for(self)
        port_path_or_id = NewRelic::Agent::Instrumentation::Redis.port_path_or_id_for(self)

        segment = NewRelic::Agent::Tracer.start_datastore_segment(
          product: NewRelic::Agent::Datastores::Redis::PRODUCT_NAME,
          operation: NewRelic::Agent::Datastores::Redis::CONNECT,
          host: hostname,
          port_path_or_id: port_path_or_id,
          database_name: db
        )

        begin
          NewRelic::Agent::Tracer.capture_segment_error segment do
            super
          end
        ensure
          segment.finish if segment
        end
      end

    end
  end
end