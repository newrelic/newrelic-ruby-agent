# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/datastores'
require 'new_relic/agent/datastores/redis'

DependencyDetection.defer do
  named :redis

  depends_on do
    defined? ::Redis
  end

  depends_on do
    NewRelic::Agent::Datastores::Redis.is_supported_version?
  end

  executes do
    NewRelic::Agent.logger.info 'Installing Redis Instrumentation'

    Redis::Client.class_eval do
      alias_method :call_without_new_relic, :call

      def call(*args, &block)
        operation = args[0][0]
        statement = ::NewRelic::Agent::Datastores::Redis.format_command(args[0])

        callback = Proc.new do |result, _, elapsed|
          NewRelic::Agent::Datastores.notice_statement(statement, elapsed)
        end

        NewRelic::Agent::Datastores.wrap('Redis', operation, nil, callback) do
          call_without_new_relic(*args, &block)
        end
      end

      alias_method :call_pipeline_without_new_relic, :call_pipeline

      def call_pipeline(*args, &block)
        pipeline = args[0]
        operation = pipeline.is_a?(::Redis::Pipeline::Multi) ? 'multi' : 'pipeline'
        statement = ::NewRelic::Agent::Datastores::Redis.format_commands(pipeline.commands)

        callback = Proc.new do |result, _, elapsed|
          NewRelic::Agent::Datastores.notice_statement(statement, elapsed)
        end

        NewRelic::Agent::Datastores.wrap('Redis', operation, nil, callback) do
          call_pipeline_without_new_relic(*args, &block)
        end
      end

      alias_method :connect_without_new_relic, :connect

      def connect(*args, &block)
        NewRelic::Agent::Datastores.wrap('Redis', 'connect') do
          connect_without_new_relic(*args, &block)
        end
      end
    end
  end
end
