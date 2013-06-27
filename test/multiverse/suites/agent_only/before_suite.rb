# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

ENV["NEWRELIC_ENABLED"] = "false"
require 'newrelic_rpm'

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

ENV["NEWRELIC_ENABLED"] = "true"
NewRelic::Agent.manual_start
