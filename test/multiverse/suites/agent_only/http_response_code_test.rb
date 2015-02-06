# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# https://newrelic.atlassian.net/browse/RUBY-765
require 'fake_collector'

class HttpResponseCodeTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  def test_request_entity_too_large
    $collector.stub_exception('metric_data', {'error_type' => 'RuntimeError', 'message' => 'too much'}, 413)

    NewRelic::Agent.increment_metric('Custom/too_big')
    assert_metrics_recorded(['Custom/too_big'])

    agent.send(:harvest_and_send_timeslice_data)

    # make sure the data gets thrown away after we called collector without crashing
    assert_metrics_not_recorded(['Custom/too_big'])
    assert_equal(1, $collector.calls_for('metric_data').size)
  end

  def test_unsupported_media_type
    $collector.stub_exception('metric_data', {'error_type' => 'RuntimeError', 'message' => 'looks bad'}, 415)

    NewRelic::Agent.increment_metric('Custom/too_big')
    assert_metrics_recorded(['Custom/too_big'])

    agent.send(:harvest_and_send_timeslice_data)

    # make sure the data gets thrown away after we called collector without crashing
    assert_metrics_not_recorded(['Custom/too_big'])
    assert_equal(1, $collector.calls_for('metric_data').size)
  end
end
