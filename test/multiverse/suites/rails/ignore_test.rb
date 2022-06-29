# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# https://newrelic.atlassian.net/browse/RUBY-927

require './app'

class IgnoredController < ApplicationController
  newrelic_ignore :only => :action_to_ignore
  newrelic_ignore_apdex :only => :action_to_ignore_apdex

  def action_to_ignore
    render body: "Ignore this"
  end

  def action_to_ignore_apdex
    render body: "This too"
  end

  def action_not_ignored
    render body: "Not this!"
  end
end

class ParentController < ApplicationController
  newrelic_ignore_apdex

  def foo(*args); end

  add_transaction_tracer :foo
end

class ChildController < ParentController
  def bar(*args); end

  add_transaction_tracer :bar
end

class IgnoredActionsTest < ActionDispatch::IntegrationTest
  include MultiverseHelpers

  setup_and_teardown_agent(:cross_process_id => "boo",
    :encoding_key => "\0",
    :trusted_account_ids => [1])

  def after_setup
    # Make sure we've got a blank slate for doing easier metric comparisons
    NewRelic::Agent.instance.drop_buffered_data
  end

  def test_metric__ignore
    get '/ignored/action_to_ignore'
    assert_metrics_recorded_exclusive([])
  end

  def test_metric__ignore_apdex
    get '/ignored/action_to_ignore_apdex'
    assert_metrics_recorded(["Controller/ignored/action_to_ignore_apdex"])
    assert_metrics_not_recorded(["Apdex"])
  end

  def test_ignored_transaction_traces_dont_leak
    get '/ignored/action_to_ignore'
    get '/request_stats/stats_action'

    trace = last_transaction_trace
    assert_equal 1, trace.root_node.children.count
  end

  def test_should_not_write_cat_response_headers_for_ignored_transactions
    get '/ignored/action_to_ignore',
      headers: {'X-NewRelic-ID' => Base64.encode64('1#234')}
    refute @response.headers["X-NewRelic-App-Data"]
  end

  def test_apdex_ignored_if_ignored_in_parent_class
    get '/child/foo'
    get '/child/bar'

    assert_metrics_not_recorded("Apdex")
  end

  def test_ignored_transaction_does_not_record_span_events
    get '/ignored/action_to_ignore'

    last_span_events = NewRelic::Agent.agent.span_event_aggregator.harvest![1]
    assert_empty last_span_events
  end

  def test_ignored_by_ignore_url_regexes_does_not_record_span_events
    with_config(:rules => {:ignore_url_regexes => ['/ignored/action_not_ignored']}) do
      get '/ignored/action_not_ignored'

      last_span_events = NewRelic::Agent.agent.span_event_aggregator.harvest![1]
      assert_empty last_span_events
    end
  end
end
