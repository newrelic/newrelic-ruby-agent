# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class StartupShutdown < Performance::TestCase
  def test_startup_shutdown
    measure do
      NewRelic::Agent.manual_start
      NewRelic::Agent.shutdown
    end
  end
end
