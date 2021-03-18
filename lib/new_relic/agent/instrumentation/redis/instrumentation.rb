# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Redis
    UNKNOWN = "unknown"
    LOCALHOST = "localhost"

    def call_with_tracing command
      operation = command[0]
      statement = ::NewRelic::Agent::Datastores::Redis.format_command(command)

      segment = NewRelic::Agent::Tracer.start_datastore_segment(
        product: NewRelic::Agent::Datastores::Redis::PRODUCT_NAME,
        operation: operation,
        host: _nr_hostname,
        port_path_or_id: _nr_port_path_or_id,
        database_name: db
      )
      begin
        segment.notice_nosql_statement(statement) if statement
        NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
      ensure
        segment.finish if segment
      end
    end

    def call_pipeline_with_tracing pipeline
      operation = pipeline.is_a?(::Redis::Pipeline::Multi) ? NewRelic::Agent::Datastores::Redis::MULTI_OPERATION : NewRelic::Agent::Datastores::Redis::PIPELINE_OPERATION
      statement = ::NewRelic::Agent::Datastores::Redis.format_pipeline_commands(pipeline.commands)

      segment = NewRelic::Agent::Tracer.start_datastore_segment(
        product: NewRelic::Agent::Datastores::Redis::PRODUCT_NAME,
        operation: operation,
        host: _nr_hostname,
        port_path_or_id: _nr_port_path_or_id,
        database_name: db
      )
      begin
        segment.notice_nosql_statement(statement)
        NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
      ensure
        segment.finish if segment
      end
    end

    def connect_with_tracing
      segment = NewRelic::Agent::Tracer.start_datastore_segment(
        product: NewRelic::Agent::Datastores::Redis::PRODUCT_NAME,
        operation: NewRelic::Agent::Datastores::Redis::CONNECT,
        host: _nr_hostname,
        port_path_or_id: _nr_port_path_or_id,
        database_name: db
      )

      begin
        NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
      ensure
        segment.finish if segment
      end
    end

    private

    def _nr_hostname
      self.path ? LOCALHOST : self.host
    rescue => e
      NewRelic::Agent.logger.debug "Failed to retrieve Redis host: #{e}"
      UNKNOWN
    end

    def _nr_port_path_or_id
      self.path || self.port
    rescue => e
      NewRelic::Agent.logger.debug "Failed to retrieve Redis port_path_or_id: #{e}"
      UNKNOWN
    end
  end
end