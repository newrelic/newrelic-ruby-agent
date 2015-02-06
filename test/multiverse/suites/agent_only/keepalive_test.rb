# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'newrelic_rpm'

class KeepaliveTest < Minitest::Test
  include MultiverseHelpers

  def test_can_reestablish_connection
    setup_agent(:aggressive_keepalive => true)

    NewRelic::Agent.agent.send(:transmit_data)

    # This is simulating the remote peer closing the TCP connection between
    # harvest cycles.
    $collector.last_socket.close

    NewRelic::Agent.agent.send(:transmit_data)

    metric_data_calls = $collector.calls_for('metric_data')
    assert_equal(2, metric_data_calls.size)
  end
end
