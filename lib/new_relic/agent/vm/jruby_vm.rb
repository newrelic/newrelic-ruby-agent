# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/vm/vm_base'

module NewRelic
  module Agent
    module VM
      class JRubyVM < VMBase
        def gather_stats(snap)
          # TODO: Which can we gather here?
        end
      end
    end
  end
end
