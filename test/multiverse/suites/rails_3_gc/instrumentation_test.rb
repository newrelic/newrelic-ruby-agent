require "action_controller/railtie"
require "rails/test_unit/railtie"
require 'rails/test_help'
require 'test/unit'

# BEGIN RAILS APP

class MyApp < Rails::Application
  config.active_support.deprecation = :log
  config.secret_token = '!*#$#' * 31
end
MyApp.initialize!

MyApp.routes.draw do
  match '/:controller(/:action(/:id))'
end

class ApplicationController < ActionController::Base; end

class TestController < ApplicationController
  include Rails.application.routes.url_helpers
  def gc_action
    GC.disable

    long_string = "01234567" * 100_000
    long_string = nil
    another_long_string = "01234567" * 100_000

    start = Time.now
    GC.enable
    GC.start
    stop = Time.now

    @duration = stop.to_f - start.to_f

    render :text => @duration.to_s
  ensure
    GC.enable
  end
end

# END RAILS APP

class TestControllerTest < ActionController::TestCase
  tests TestController
  def setup
    enable_gc_stats

    @controller = TestController.new
    NewRelic::Agent.instance.stats_engine.reset_stats
    NewRelic::Agent.instance.transaction_sampler \
      .instance_variable_set(:@samples, [])
    NewRelic::Agent.manual_start
  end

  def teardown
    NewRelic::Agent.shutdown
  end

  def enable_gc_stats
    if RUBY_DESCRIPTION =~ /Enterprise/
      GC.enable_stats
    elsif RUBY_VERSION >= '1.9.2'
      GC::Profiler.enable
    end
  end
end

class GCRailsInstrumentationTest < TestControllerTest
  def test_records_accurate_time_for_gc_activity
    get :gc_action

    assert_in_delta(assigns[:duration],
                    NewRelic::Agent.agent.stats_engine \
                      .get_stats('GC/cumulative') \
                      .total_call_time, 0.1,
                    'problem with unscoped GC metric')
    assert_in_delta(assigns[:duration],
                    NewRelic::Agent.agent.stats_engine \
                      .get_stats('GC/cumulative', true, false,
                                 'Controller/test/gc_action') \
                      .total_call_time, 0.1,
                    'problem with scoped GC metric')
  end

  def test_records_transaction_param_for_gc_activity
    get :gc_action

    trace = NewRelic::Agent.instance.transaction_sampler.last_sample
    assert_in_delta(assigns[:duration], trace.params[:custom_params][:gc_time], 0.1)
  end
end
