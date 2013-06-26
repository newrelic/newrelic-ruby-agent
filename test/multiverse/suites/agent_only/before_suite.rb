# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# Ugly, but we don't really want/need a public API to the agent's worker thread
thread = NewRelic::Agent.instance.instance_variable_get(:@worker_thread)
thread.kill if thread

# Redefine so we don't restart the thread accidentally
module NewRelic
  module Agent
    class Agent
      def start_worker_thread(*)
        NewRelic::Agent.logger.debug("Overridden start_worker_thread, so not starting!")
      end
    end
  end
end
