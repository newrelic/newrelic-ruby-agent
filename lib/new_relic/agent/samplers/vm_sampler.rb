# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/sampler'
require 'new_relic/agent/vm'

module NewRelic
  module Agent
    module Samplers
      class VMSampler
        def self.supported_on_this_platform?
          true
        end

        def poll
          snapshot = NewRelic::Agent::VM.snapshot
          NewRelic::Agent.record_metric('RubyVM/Threads/all', :count => snapshot.thread_count)
        end
      end
    end
  end
end
