# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative 'instrumentation'

module NewRelic
  module Agent
    module Instrumentation
      module Thread
        module Prepend
          include NewRelic::Agent::Instrumentation::Thread

          def initialize(*args, &block)
            initialize_with_newrelic_tracing { super }
          end
        end
      end
    end
  end
end
