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

        NewRelic::Agent::Datastores.wrap('Redis', operation) do
          call_without_new_relic(*args, &block)
        end
      end
    end
  end
end
