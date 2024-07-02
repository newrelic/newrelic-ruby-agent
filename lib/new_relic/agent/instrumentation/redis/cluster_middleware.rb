# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module RedisClient
    module ClusterMiddleware
      include NewRelic::Agent::Instrumentation::Redis

      # Until we decide to move our Redis instrumentation entirely off patches
      # keep the middleware instrumentation for the call and connect methods
      # limited to the redis-clustering instrumentation.
      #
      # Redis's middleware option does not capture errors as high in the stack
      # as our patches. Leaving the patches for call and connect on the main
      # Redis gem limits the feature disparity our customers experience.
      def call(*args, &block)
        call_with_tracing(args[0]) { super }
      end

      def connect(*args, &block)
        connect_with_tracing { super }
      end
    end
  end
end
