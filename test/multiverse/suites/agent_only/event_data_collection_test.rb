# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'newrelic_rpm'

class EventDataCollectionTest < Minitest::Test
  include MultiverseHelpers

  def test_sends_all_event_data_on_connect
    expected = {
      'harvest_limits' => {
        "analytic_event_data" => 1200,
        "custom_event_data" => 1000,
        "error_event_data" => 100
      }
    }

    setup_agent

    assert_equal expected, single_connect_posted['event_data']
  end
end