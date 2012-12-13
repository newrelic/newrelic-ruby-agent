# https://newrelic.atlassian.net/browse/RUBY-927

ENV['NEW_RELIC_DISPATCHER'] = 'test'

require 'action_controller/railtie'
require 'rails/test_unit/railtie'
require 'rails/test_help'
require 'test/unit'

# BEGIN RAILS APP

class MyApp < Rails::Application
  # We need a secret token for session, cookies, etc.
  config.active_support.deprecation = :log
  config.secret_token = "49837489qkuweoiuoqwehisuakshdjksadhaisdy78o34y138974xyqp9rmye8yrpiokeuioqwzyoiuxftoyqiuxrhm3iou1hrzmjk"
end
MyApp.initialize!

MyApp.routes.draw do
  match '/:controller(/:action(/:id))'
end

class ApplicationController < ActionController::Base; end

class TestController < ApplicationController
  include Rails.application.routes.url_helpers

  def queued
    respond_to do |format|
      format.html { render :text => "<html><head></head><body>Queued</body></html>" }
    end
  end
end
# END RAILS APP

class QueueTimeTest < ActionDispatch::IntegrationTest
  def setup
    NewRelic::Agent.config.apply_config({
      :beacon => "beacon",
      :browser_key => "key"})

    @agent = NewRelic::Agent::Agent.new
    NewRelic::Agent::Agent.instance_variable_set(:@instance, @agent)
    NewRelic::Agent.manual_start

    @agent.finish_setup({})
  end

  def teardown
    NewRelic::Agent::Agent.instance.shutdown if NewRelic::Agent::Agent.instance
  end

  def test_should_track_queue_time_metric
    get_queued

    stat = @agent.stats_engine.lookup_stats('WebFrontend/QueueTime')
    assert_equal 1, stat.call_count
    assert stat.total_call_time > 0, "Should track some queue time"
  end

  def test_should_see_queue_time_in_rum
    get_queued
    assert extract_queue_time_from_response > 0, "Queue time was missing or zero"
  end

  def get_queued(header="HTTP_X_QUEUE_START")
    get('/test/queued', nil, \
        header => "t=#{(Time.now.to_i * 1_000_000) - 1_000}")
  end

  def extract_queue_time_from_response
    @response.body =~ /key\","",\".*\",(\d+.*),\d+,new Date/
    $1.to_i
  end
end
