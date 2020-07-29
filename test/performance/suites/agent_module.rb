# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

# This suite is for perf testing methods from the NewRelic::Agent module

class AgentModuleTest < Performance::TestCase
  METRIC = "Some/Custom/Metric".freeze

  def test_increment_metric_by_1
    measure do
      NewRelic::Agent.increment_metric(METRIC)
    end
  end

  def test_increment_metric_by_more_than_1
    measure do
      NewRelic::Agent.increment_metric(METRIC, 2)
    end
  end
end
