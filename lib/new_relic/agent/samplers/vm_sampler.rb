# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/sampler'
require 'new_relic/agent/vm'

module NewRelic
  module Agent
    module Samplers
      class VMSampler < Sampler
        attr_reader :transaction_count

        def initialize
          super :vm
          @lock = Mutex.new
          @transaction_count = 0
        end

        def setup_events(event_listener)
          event_listener.subscribe(:transaction_finished, &method(:on_transaction_finished))
        end

        def on_transaction_finished(*_)
          @lock.synchronize { @transaction_count += 1 }
        end

        def poll
          snapshot = NewRelic::Agent::VM.snapshot
          NewRelic::Agent.record_metric('RubyVM/Threads/all', :count => snapshot.thread_count)
        end
      end
    end
  end
end
