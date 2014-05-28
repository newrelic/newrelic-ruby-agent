# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# https://newrelic.atlassian.net/browse/RUBY-927

require './app'

class QueueController < ApplicationController
  def queued
    respond_to do |format|
      format.html { render :text => "<html><head></head><body>Queued</body></html>" }
    end
  end

  def nested
    nested_transaction
    render :text => 'whatever'
  end

  def nested_transaction; end

  add_transaction_tracer :nested_transaction
end

class QueueTimeTest < RailsMultiverseTest

  REQUEST_START_HEADER = 'HTTP_X_REQUEST_START'

  include MultiverseHelpers

  setup_and_teardown_agent(:beacon => "beacon", :browser_key => "key", :js_agent_loader => "loader")

  def test_should_track_queue_time_metric
    t0 = freeze_time
    t1 = advance_time(2)
    get_path('/queue/queued', t0)

    assert_metrics_recorded(
      'WebFrontend/QueueTime' => {
        :call_count      => 1,
        :total_call_time => (t1 - t0)
      }
    )
  end

  def test_should_see_queue_time_in_rum
    t0 = freeze_time
    t1 = advance_time(2)
    get_path('/queue/queued', t0)
    queue_time = extract_queue_time_from_response
    assert_equal((t1 - t0) * 1000, queue_time)
  end

  def test_should_not_track_queue_time_for_nested_transactions
    t0 = freeze_time
    t1 = advance_time(2)
    get_path('/queue/nested', t0)
    assert_metrics_recorded(
      'WebFrontend/QueueTime' => {
        :call_count      => 1,
        :total_call_time => (t1 - t0)
      }
    )
  end

  def get_path(path, queue_start_time)
    value = "t=#{(queue_start_time.to_f * 1_000_000).to_i}"
    get(path, nil, REQUEST_START_HEADER => value)
  end

  def extract_queue_time_from_response
    get_last_response_body =~ /\"queueTime\":(\d+.*)/
    refute_nil $1, "Should have found queue time in #{@response.body.inspect}"
    $1.to_i
  end

  def get_last_response_body
    if Rails::VERSION::MAJOR >= 3
      @response.body
    else
      # In Rails 2 integration tests, @response.body is always the response from
      # the controller itself, not the middleware stack. Since we want the
      # response from the middleware stack, we grab it off of the integration
      # session.
      @integration_session.body
    end
  end
end
