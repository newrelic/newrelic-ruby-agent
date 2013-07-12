# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# https://newrelic.atlassian.net/browse/RUBY-927

require 'rails/test_help'
require './app'
require 'multiverse_helpers'

class QueueController < ApplicationController
  include Rails.application.routes.url_helpers

  def queued
    respond_to do |format|
      format.html { render :text => "<html><head></head><body>Queued</body></html>" }
    end
  end
end

class QueueTimeTest < ActionDispatch::IntegrationTest

  include MultiverseHelpers

  setup_and_teardown_agent(:beacon => "beacon", :browser_key => "key")

  def test_should_track_queue_time_metric
    get_queued

    stat = agent.stats_engine.lookup_stats('WebFrontend/QueueTime')
    assert_equal 1, stat.call_count
    assert stat.total_call_time > 0, "Should track some queue time"
  end

  def test_should_see_queue_time_in_rum
    get_queued
    assert extract_queue_time_from_response > 0, "Queue time was missing or zero"
  end

  def get_queued(header="HTTP_X_REQUEST_START")
    value = "t=#{(Time.now.to_i * 1_000_000) - 1_000}"
    get('/queue/queued', nil, header => value)
  end

  def extract_queue_time_from_response
    @response.body =~ /key\","",\".*\",(\d+.*),\d+,new Date/
    $1.to_i
  end
end
