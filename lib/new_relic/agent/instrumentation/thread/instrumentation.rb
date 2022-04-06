# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic
  module Agent
    module Instrumentation
      module Thread
        attr_reader :nr_parent_thread_id

        def initialize_with_newrelic_tracing # (*args, &block)
          # grab parent
          puts "itsa thread waluigi"
          @nr_parent_thread_id = ::Thread.current.object_id
          yield
        end
      end
    end
  end
end
