# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic
  module Agent
    module Threading
      # This class is used internally by the agent to prevent agent threads from sharing a state with application threads
      class InternalThread < ::Thread
        def skip_tracing?
          true
        end
      end
    end
  end
end
