# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

class NewRelic::Agent::StatsEngine::GCProfilerTest < Test::Unit::TestCase
  def test_init_profiler_for_rails_bench
    return unless defined?(::GC) && ::GC.respond_to?(:collections)

    ::GC.stubs(:time)
    ::GC.stubs(:collections)

    assert_equal(NewRelic::Agent::StatsEngine::GCProfiler::RailsBenchProfiler,
                 NewRelic::Agent::StatsEngine::GCProfiler.init.class)
  end

  def test_init_profiler_for_ruby_19_and_greater
    return unless defined?(::GC::Profiler)
    return if NewRelic::LanguageSupport.using_engine?('jruby')

    ::GC::Profiler.stubs(:enabled?).returns(true)
    ::GC::Profiler.stubs(:total_time).returns(0)
    ::GC.stubs(:count).returns(0)

    assert_equal(NewRelic::Agent::StatsEngine::GCProfiler::CoreGCProfiler,
                 NewRelic::Agent::StatsEngine::GCProfiler.init.class)
  end

  def test_init_profiler_for_rbx_uses_stdlib
    return unless defined?(::Rubinius::GC)

    assert_equal(NewRelic::Agent::StatsEngine::GCProfiler::CoreGCProfiler,
                 NewRelic::Agent::StatsEngine::GCProfiler.init.class)
  end

  def test_collect_gc_data
    return if NewRelic::LanguageSupport.using_engine?('jruby')

    GC.disable
    if NewRelic::LanguageSupport.using_version?('1.9')
      ::GC::Profiler.stubs(:enabled?).returns(true)
      ::GC::Profiler.stubs(:total_time).returns(1.0, 4.0)
      ::GC.stubs(:count).returns(1, 3)
      ::GC::Profiler.stubs(:clear).returns(nil)
    elsif NewRelic::LanguageSupport.using_version?('1.8.7') &&
        RUBY_DESCRIPTION =~ /Ruby Enterprise Edition/
      ::GC.stubs(:time).returns(1000000, 4000000)
      ::GC.stubs(:collections).returns(1, 3)
    else
      return true # no need to test if we're not collecting GC metrics
    end

    with_config(:'transaction_tracer.enabled' => true) do
      in_transaction { }
    end

    engine = NewRelic::Agent.instance.stats_engine
    tracer = NewRelic::Agent.instance.transaction_sampler

    gc_stats = engine.get_stats('GC/cumulative')
    assert_equal 2, gc_stats.call_count
    assert_equal 3.0, gc_stats.total_call_time
    assert_equal(3.0, tracer.last_sample.params[:custom_params][:gc_time])
  end
end
