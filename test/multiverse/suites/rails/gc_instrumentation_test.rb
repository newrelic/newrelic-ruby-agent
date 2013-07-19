# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require './app'
require 'multiverse_helpers'

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

  include MultiverseHelpers

  setup_and_teardown_agent do
    enable_gc_stats
    @controller = GcController.new
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
    assert gc_time < duration, "GC Time can't be more than elapsed!"
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
