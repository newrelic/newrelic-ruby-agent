# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/datastores'
require 'new_relic/agent/datastores/redis'

DependencyDetection.defer do
  # Why not :redis? newrelic-redis used that name, so avoid conflicting
  named :redis_instrumentation

  depends_on do
    defined? ::Redis
  end

  depends_on do
    NewRelic::Agent.config[:disable_redis] == false
  end

  depends_on do
    NewRelic::Agent::Datastores::Redis.is_supported_version? &&
      NewRelic::Agent::Datastores::Redis.safe_from_third_party_gem?
  end

  executes do
    NewRelic::Agent.logger.info 'Installing Redis Instrumentation'

    Redis::Client.class_eval do
      alias_method :call_without_new_relic, :call

      def call(*args, &block)
        operation = args[0][0]
        statement = ::NewRelic::Agent::Datastores::Redis.format_command(args[0])

        if statement
          callback = Proc.new do |result, _, elapsed|
            NewRelic::Agent::Datastores.notice_statement(statement, elapsed)
          end
        end

        NewRelic::Agent::Datastores.wrap(NewRelic::Agent::Datastores::Redis::PRODUCT_NAME, operation, nil, callback) do
          call_without_new_relic(*args, &block)
        end
      end

      alias_method :call_pipeline_without_new_relic, :call_pipeline

      def call_pipeline(*args, &block)
        pipeline = args[0]
        operation = pipeline.is_a?(::Redis::Pipeline::Multi) ? NewRelic::Agent::Datastores::Redis::MULTI_OPERATION : NewRelic::Agent::Datastores::Redis::PIPELINE_OPERATION
        statement = ::NewRelic::Agent::Datastores::Redis.format_pipeline_commands(pipeline.commands)

        callback = Proc.new do |result, _, elapsed|
          NewRelic::Agent::Datastores.notice_statement(statement, elapsed)
        end

        NewRelic::Agent::Datastores.wrap(NewRelic::Agent::Datastores::Redis::PRODUCT_NAME, operation, nil, callback) do
          call_pipeline_without_new_relic(*args, &block)
        end
      end

      alias_method :connect_without_new_relic, :connect

      def connect(*args, &block)
        NewRelic::Agent::Datastores.wrap(NewRelic::Agent::Datastores::Redis::PRODUCT_NAME, NewRelic::Agent::Datastores::Redis::CONNECT) do
          connect_without_new_relic(*args, &block)
        end
      end
    end
  end
end
