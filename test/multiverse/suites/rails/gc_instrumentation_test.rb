# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require './app'

# GC instrumentation only works with REE or 1.9.x
if (defined?(RUBY_DESCRIPTION) && RUBY_DESCRIPTION =~ /Enterprise/) ||
    RUBY_VERSION >= '1.9.2'

class GcController < ApplicationController
  include Rails.application.routes.url_helpers
  def gc_action
    long_string = "01234567" * 100_000
    long_string = nil
    another_long_string = "01234567" * 100_000

    GC.start

    render :text => 'ha'
  end
end

class GCRailsInstrumentationTest < ActionController::TestCase
  tests GcController
  def setup
    enable_gc_stats

    @controller = GcController.new
    NewRelic::Agent.instance.stats_engine.reset_stats
    NewRelic::Agent.instance.transaction_sampler.instance_variable_set(:@samples, [])
    NewRelic::Agent.manual_start
  end

  def teardown
    NewRelic::Agent.shutdown
  end

  def test_records_accurate_time_for_gc_activity
    start = Time.now
    get :gc_action
    elapsed = Time.now.to_f - start.to_f

    assert_in_range(elapsed, get_call_time('GC/cumulative'))
    assert_in_range(elapsed, get_call_time('GC/cumulative', 'Controller/gc/gc_action'))
  end

  def test_records_transaction_param_for_gc_activity
    start = Time.now.to_f
    get :gc_action
    elapsed = Time.now.to_f - start

    trace = NewRelic::Agent.instance.transaction_sampler.last_sample
    assert_in_range(elapsed, trace.params[:custom_params][:gc_time])
  end

  def assert_in_range(duration, gc_time)
    assert gc_time > 0.0, "GC Time wasn't recorded!"

    # This is a guess for a reasonable threshold here.
    # Since these are timing based, we can revise or ditch as evidence ditacts
    # One CI failure we saw at least had duration=0.314 and gc_time=0.088
    ratio = gc_time / duration
    assert(ratio > 0.1 && ratio < 1.0,
      "Problem with GC/duration ratio. #{gc_time}/#{duration} = #{ratio} not between 0.1 and 1.0")
  end

  def get_call_time(name, scope=nil)
    NewRelic::Agent.agent.stats_engine.
      get_stats(name, true, false, scope).
      total_call_time
  end

  def enable_gc_stats
    if RUBY_DESCRIPTION =~ /Enterprise/
      GC.enable_stats
    elsif RUBY_VERSION >= '1.9.2'
      GC::Profiler.enable
    end
  end
end

end
