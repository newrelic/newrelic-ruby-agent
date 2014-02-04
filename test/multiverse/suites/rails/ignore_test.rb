# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# https://newrelic.atlassian.net/browse/RUBY-927

require 'rails/test_help'
require './app'
require 'multiverse_helpers'

class IgnoredController < ApplicationController
  include Rails.application.routes.url_helpers

  newrelic_ignore :only => :action_to_ignore
  newrelic_ignore_apdex :only => :action_to_ignore_apdex

  def action_to_ignore
    render :text => "Ignore this"
  end

  def action_to_ignore_apdex
    render :text => "This too"
  end
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
    get 'ignored/action_to_ignore'
    assert_metrics_recorded_exclusive([])
  end

  def test_metric__ignore_apdex
    get 'ignored/action_to_ignore_apdex'
    assert_metrics_recorded(["Controller/ignored/action_to_ignore_apdex"])
    assert_metrics_not_recorded(["Apdex"])
  end

  def test_should_not_write_cat_response_headers_for_ignored_transactions
    get 'ignored/action_to_ignore', nil, {'X-NewRelic-ID' => Base64.encode64('1#234')}
    assert_nil @response.headers["X-NewRelic-App-Data"]
  end
end
