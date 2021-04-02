# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic::Agent::Instrumentation
  module Padrino
    module Prepend
      include NewRelic::Agent::Instrumentation::Sinatra
      include NewRelic::Agent::Instrumentation::Padrino

      def dispatch
        dispatch_with_tracing { super }
      end

      def invoke_route(*args, &block)
        invoke_route_with_tracing(*args) { super }
      end
    end
  end
end