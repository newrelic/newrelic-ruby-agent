# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class StartupShutdown < Performance::TestCase
  def test_startup_shutdown
    measure(1) do
      NewRelic::Agent.manual_start
      NewRelic::Agent.shutdown
    end
  end
end
