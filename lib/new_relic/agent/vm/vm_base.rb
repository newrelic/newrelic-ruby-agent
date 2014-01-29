# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/vm/snapshot'

module NewRelic
  module Agent
    module VM
      class VMBase
        def snapshot
          snap = Snapshot.new
          gather_stats(snap)
          snap
        end

        def gather_stats(snap)
          raise NotImplementedError("VM subclasses expected to implement gather_stats")
        end

        def supports?(key)
          false
        end
      end
    end
  end
end
