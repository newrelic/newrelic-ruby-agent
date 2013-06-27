# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module MultiverseHelpers
  def setup_collector
    $collector ||= NewRelic::FakeCollector.new
    $collector.reset
    $collector.run

    if (NewRelic::Agent.instance &&
        NewRelic::Agent.instance.service &&
        NewRelic::Agent.instance.service.collector)
      NewRelic::Agent.instance.service.collector.port = $collector.port
    end
  end

  def reset_collector
    $collector.reset
  end
end
