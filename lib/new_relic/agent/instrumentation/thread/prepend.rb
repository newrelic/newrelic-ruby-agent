# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative 'instrumentation'

module NewRelic
  module Agent
    module Instrumentation
      module ThreadMonitor
        module Prepend
          include NewRelic::Agent::Instrumentation::ThreadMonitor

          def initialize(*args, &block)
            traced_block = add_thread_tracing(*args, &block)
            initialize_with_newrelic_tracing { super(*args, &traced_block) }
          end
        end
      end
    end
  end
end
