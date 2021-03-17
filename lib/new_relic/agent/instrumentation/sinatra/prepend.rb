# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative 'instrumentation'

module NewRelic::Agent::Instrumentation
  module SinatraInstrumentation
    module Prepend 
      
      def dispatch!
        dispatch_with_tracing { super }
      end

      def process_route(*args, &block)
        process_route_with_tracing(*args) do 
          super
        end
      end

      def route_eval(*args, &block)
        route_eval_with_tracing(*args) do
          super
        end
      end

    end

    module PrependBuild
      def build(*args, &block)
        build_with_tracing(*args) do
          super
        end
      end
    end
  end
end

