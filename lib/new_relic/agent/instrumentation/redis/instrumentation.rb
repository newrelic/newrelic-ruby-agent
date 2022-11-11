# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Redis
    PRODUCT_NAME = 'Redis'
    CONNECT = 'connect'
    UNKNOWN = 'unknown'
    LOCALHOST = 'localhost'
    MULTI_OPERATION = 'multi'
    PIPELINE_OPERATION = 'pipeline'
    HAS_REDIS_CLIENT = Gem::Version.new(::Redis::VERSION) >= Gem::Version.new('5.0.0') && !!defined?(::RedisClient)

    def connect_with_tracing
      with_tracing(CONNECT, database: db) { yield }
    end

    # Used for Redis 4.x and 3.x
    def call_with_tracing(command, &block)
      operation = command[0]
      statement = ::NewRelic::Agent::Datastores::Redis.format_command(command)

      with_tracing(operation, statement: statement, database: db) { yield }
    end

    # Used for Redis 4.x and 3.x
    def call_pipeline_with_tracing(pipeline)
      operation = pipeline.is_a?(::Redis::Pipeline::Multi) ? MULTI_OPERATION : PIPELINE_OPERATION
      statement = ::NewRelic::Agent::Datastores::Redis.format_pipeline_commands(pipeline.commands)

      with_tracing(operation, statement: statement, database: db) { yield }
    end

    # Used for Redis 5.x
    def call_pipelined_with_tracing(pipeline)
      operation = pipeline.flatten.include?('MULTI') ? MULTI_OPERATION : PIPELINE_OPERATION
      statement = ::NewRelic::Agent::Datastores::Redis.format_pipeline_commands(pipeline)

      # call_pipelined isn't invoked on the client object, so use client.db to
      # access the client instance var on self
      with_tracing(operation, statement: statement, database: client.db) { yield }
    end

    # Used for Redis 5.x
    def call_v_with_tracing(command, &block)
      operation = command[0]
      statement = ::NewRelic::Agent::Datastores::Redis.format_command(command)
      with_tracing(operation, statement: statement, database: db) { yield }
    end

    private

    def with_tracing(operation, statement: nil, database: nil)
      segment = NewRelic::Agent::Tracer.start_datastore_segment(
        product: PRODUCT_NAME,
        operation: operation,
        host: _nr_hostname,
        port_path_or_id: _nr_port_path_or_id,
        database_name: database
      )
      begin
        segment.notice_nosql_statement(statement) if statement
        NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
      ensure
        segment.finish if segment
      end
    end

    def _nr_hostname
      _nr_client.path ? LOCALHOST : _nr_client.host
    rescue => e
      NewRelic::Agent.logger.debug("Failed to retrieve Redis host: #{e}")
      UNKNOWN
    end

    def _nr_port_path_or_id
      _nr_client.path || _nr_client.port
    rescue => e
      NewRelic::Agent.logger.debug("Failed to retrieve Redis port_path_or_id: #{e}")
      UNKNOWN
    end

    def _nr_client
      @nr_client ||= self.is_a?(::Redis::Client) ? self : client
    end
  end
end
