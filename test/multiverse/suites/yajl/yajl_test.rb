# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'multiverse_helpers'

# This is the problematic thing that overrides our JSON marshalling
require 'yajl/json_gem'

class YajlTest < Minitest::Test

  include MultiverseHelpers

  setup_and_teardown_agent do
    Yajl::Encoder.expects(:encode).never
  end

  def test_sends_metrics
    NewRelic::Agent.record_metric('Boo', 42)

    transmit_data

    result = $collector.calls_for('metric_data')
    assert_equal 1, result.length
    assert_includes result.first.metric_names, 'Boo'
  end

  def transmit_data
    NewRelic::Agent.instance.send(:transmit_data)
  end
end
