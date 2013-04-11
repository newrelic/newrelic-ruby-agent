# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

class NewRelic::Agent::StatsEngine::GCProfilerTest < Test::Unit::TestCase
  def test_init_profiler_for_rails_bench
    ::GC.stubs(:time)
    ::GC.stubs(:collections)

    assert_equal(NewRelic::Agent::StatsEngine::GCProfiler::RailsBench,
                 NewRelic::Agent::StatsEngine::GCProfiler.init.class)
  end

  def test_init_profiler_for_ruby_19
    defined = defined?(::GC::Profiler)
    if !defined
      ::GC.const_set(:Profiler, Module.new)
    end
    ::GC::Profiler.stubs(:enabled?).returns(true)
    ::GC::Profiler.stubs(:total_time).returns(0)
    ::GC.stubs(:count).returns(0)

    assert_equal(NewRelic::Agent::StatsEngine::GCProfiler::Ruby19,
                 NewRelic::Agent::StatsEngine::GCProfiler.init.class)
  ensure
    ::GC.send(:remove_const, :Profiler) unless defined
  end

  def test_init_profiler_for_rbx
    defined = defined?(::Rubinius::GC)
    if !defined
      Object.const_set(:Rubinius, Module.new)
      ::Rubinius.const_set(:GC, Module.new)
    end
    ::Rubinius::GC.stubs(:count).returns(0)
    ::Rubinius::GC.stubs(:time).returns(0)

    assert_equal(NewRelic::Agent::StatsEngine::GCProfiler::Rubinius,
                 NewRelic::Agent::StatsEngine::GCProfiler.init.class)
  ensure
    Object.send(:remove_const, :Rubinius) unless defined
  end

  def test_collect_gc_data
    GC.disable unless NewRelic::LanguageSupport.using_engine?('jruby')
    if NewRelic::LanguageSupport.using_engine?('rbx')
      agent = ::Rubinius::Agent.loopback
      agent.stubs(:get).with('system.gc.young.total_wallclock') \
        .returns([:value, 1000], [:value, 2500])
      agent.stubs(:get).with('system.gc.full.total_wallclock') \
        .returns([:value, 2000], [:value, 3500])
      agent.stubs(:get).with('system.gc.young.count') \
        .returns([:value, 1], [:value, 2])
      agent.stubs(:get).with('system.gc.full.count') \
        .returns([:value, 1], [:value, 2])
      ::Rubinius::Agent.stubs(:loopback).returns(agent)
    elsif NewRelic::LanguageSupport.using_version?('1.9')
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
  ensure
    GC.enable unless NewRelic::LanguageSupport.using_engine?('jruby')
  end
end
