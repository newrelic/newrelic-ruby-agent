# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'newrelic_rpm'
require 'multiverse_helpers'

class KeepaliveTest < Minitest::Test
  include MultiverseHelpers

  def test_can_reestablish_connection
    setup_agent(:aggressive_keepalive => true)

    NewRelic::Agent.agent.send(:transmit_data)

    # This is the closest I can easily get to closing the underlying TCP
    # connection from the server side in between harvests.
    conn0 = NewRelic::Agent.agent.service.http_connection
    conn0.instance_variable_get(:@socket).close

    NewRelic::Agent.agent.send(:transmit_data)

    conn1 = NewRelic::Agent.agent.service.http_connection

    metric_data_calls = $collector.calls_for('metric_data')
    assert_equal(2, metric_data_calls.size)
    assert_same(conn0, conn1)
  end
end
