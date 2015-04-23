# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'newrelic_rpm'

class CustomQueueTimeTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  DummyRequest = Struct.new(:headers, :cookies) do
    def path
      "/"
    end
  end

  class DummyApp
    include NewRelic::Agent::Instrumentation::ControllerInstrumentation

    def run_transaction(request, simulated_queue_time)
      opts = { :name => 'run_transaction', :class_name => 'DummyApp', :request => request }

      advance_time(simulated_queue_time)

      perform_action_with_newrelic_trace(opts) do
        # nothing
      end
    end
  end

  def setup
    freeze_time
    @headers = { 'HTTP_X_REQUEST_START' => "t=#{Time.now.to_f}" }
  end

  def test_pulls_request_headers_from_passed_in_rack_request
    request = Rack::Request.new(@headers)
    DummyApp.new.run_transaction(request, 10)

    assert_metrics_recorded(
      'WebFrontend/QueueTime' => {
        :call_count      => 1,
        :total_call_time => 10
      }
    )
  end

  def test_pulls_request_headers_from_passed_in_request_responding_to_headers
    request = DummyRequest.new(@headers, {})
    DummyApp.new.run_transaction(request, 10)

    assert_metrics_recorded(
      'WebFrontend/QueueTime' => {
        :call_count      => 1,
        :total_call_time => 10
      }
    )
  end
end
