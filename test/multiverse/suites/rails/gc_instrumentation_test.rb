# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require './app'

# These tests only return consistent results MRI >= 1.9.2
if !NewRelic::LanguageSupport.jruby?

class GcController < ApplicationController
  def gc_action
    begin
      NewRelic::Agent::StatsEngine::GCProfiler.init
      initial_gc_count = ::GC.count

      Timeout.timeout(5) do
        until ::GC.count > initial_gc_count
          long_string = "01234567" * 100_000
          long_string = nil
          another_long_string = "01234567" * 100_000
          another_long_string = nil
        end
      end
    rescue Timeout::Error
      puts "Timed out waiting for GC..."
    end

    render body:  'ha'
  end
end

class GCRailsInstrumentationTest < ActionController::TestCase
  tests GcController

  include MultiverseHelpers

  setup_and_teardown_agent do
    NewRelic::Agent.drop_buffered_data
    NewRelic::Agent::StatsEngine::GCProfiler.reset
    GC::Profiler.enable
    @controller = GcController.new
  end

  def test_records_accurate_time_for_gc_activity
    start = Time.now
    get :gc_action
    elapsed = Time.now.to_f - start.to_f

    stats_hash = NewRelic::Agent.instance.stats_engine.reset!

    gc_metric_unscoped = stats_hash[NewRelic::MetricSpec.new('GC/Transaction/allWeb')]
    gc_metric_scoped = stats_hash[NewRelic::MetricSpec.new('GC/Transaction/allWeb', 'Controller/gc/gc_action')]

    assert_in_range(elapsed, gc_metric_unscoped.total_call_time)
    assert_in_range(elapsed, gc_metric_scoped.total_call_time)
  end

  def test_records_transaction_param_for_gc_activity
    start = Time.now.to_f
    get :gc_action
    elapsed = Time.now.to_f - start

    trace = last_transaction_trace
    assert_in_range(elapsed, attributes_for(trace, :intrinsic)[:gc_time])
  end

  def assert_in_range(duration, gc_time)
    assert gc_time > 0.0, "GC Time wasn't recorded!"
    assert gc_time < duration, "GC Time #{gc_time} can't be more than elapsed #{duration}!"
  end
end

end
