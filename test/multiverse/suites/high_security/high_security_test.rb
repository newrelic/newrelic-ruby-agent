# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'multiverse_helpers'

class HighSecurityTest < Minitest::Test

  include MultiverseHelpers

  setup_and_teardown_agent do |collector|
    collector.stub('connect', {
      "agent_run_id" => 1,
      "listen_to_server_config" => true,
      "capture_params"          => true,
    }, 200)
  end

  def test_disallows_server_config_from_overriding_high_security
    refute NewRelic::Agent.config[:capture_params]
  end

  def test_doesnt_capture_params
    in_transaction(:filtered_params => { "loose" => "params" }) do
      # no-op
    end
    assert last_transaction_trace_request_params.empty?
  end

end
