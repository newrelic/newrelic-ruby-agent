# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..', '..','..','test_helper'))
require 'new_relic/agent/samplers/cpu_sampler'

class NewRelic::Agent::StatsEngine::SamplersTest < Minitest::Test

  class OurSamplers
    include NewRelic::Agent::StatsEngine::Samplers
  end

  class OurSampler
    attr_accessor :id, :stats_engine
  end

  def setup
    @stats_engine = NewRelic::Agent::StatsEngine.new
    NewRelic::Agent.instance.stubs(:stats_engine).returns(@stats_engine)
  end

  def test_cpu_sampler_records_user_and_system_time
    timeinfo0 = mock
    timeinfo0.stubs(:utime).returns(10.0)
    timeinfo0.stubs(:stime).returns(5.0)

    timeinfo1 = mock
    timeinfo1.stubs(:utime).returns(14.0) # +5s
    timeinfo1.stubs(:stime).returns(7.0)  # +2s

    elapsed = 10

    freeze_time
    Process.stubs(:times).returns(timeinfo0, timeinfo1)
    NewRelic::Agent::SystemInfo.stubs(:num_logical_processors).returns(4)

    s = NewRelic::Agent::Samplers::CpuSampler.new # this calls poll
    advance_time(elapsed)
    s.poll

    assert_metrics_recorded({
      'CPU/User Time'   => { :call_count => 1, :total_call_time => 4.0 },
      'CPU/System Time' => { :call_count => 1, :total_call_time => 2.0 },
      # (4s user time)   / ((10s elapsed time) * 4 cpus) = 0.1
      'CPU/User/Utilization'   => { :call_count => 1, :total_call_time => 0.1 },
      # (2s system time) / ((10s elapsed time) * 4 cpus) = 0.05
      'CPU/System/Utilization' => { :call_count => 1, :total_call_time => 0.05 }
    })
  end

  def test_memory__default
    s = NewRelic::Agent::Samplers::MemorySampler.new
    s.poll
    s.poll
    s.poll
    stats = @stats_engine.get_stats_no_scope("Memory/Physical")
    assert_equal(3, stats.call_count)
    assert stats.total_call_time > 0.5, "cpu greater than 0.5 ms: #{stats.total_call_time}"
  end

  def test_memory__linux
    return if RUBY_PLATFORM =~ /darwin/
    NewRelic::Agent::Samplers::MemorySampler.any_instance.stubs(:platform).returns 'linux'
    s = NewRelic::Agent::Samplers::MemorySampler.new
    s.poll
    s.poll
    s.poll
    stats = @stats_engine.get_stats_no_scope("Memory/Physical")
    assert_equal 3, stats.call_count
    assert stats.total_call_time > 0.5, "cpu greater than 0.5 ms: #{stats.total_call_time}"
  end

  def test_memory__solaris
    return if defined? JRuby
    NewRelic::Agent::Samplers::MemorySampler.any_instance.stubs(:platform).returns 'solaris'
    NewRelic::Agent::Samplers::MemorySampler::ShellPS.any_instance.stubs(:get_memory).returns 999
    s = NewRelic::Agent::Samplers::MemorySampler.new
    s.poll
    stats = @stats_engine.get_stats_no_scope("Memory/Physical")
    assert_equal 1, stats.call_count
    assert_equal 999, stats.total_call_time
  end

  def test_memory__windows
    return if defined? JRuby
    NewRelic::Agent::Samplers::MemorySampler.any_instance.stubs(:platform).returns 'win32'
    assert_raises NewRelic::Agent::Sampler::Unsupported do
      NewRelic::Agent::Samplers::MemorySampler.new
    end
  end

  def test_memory__is_supported
    NewRelic::Agent::Samplers::MemorySampler.stubs(:platform).returns 'windows'
    assert !NewRelic::Agent::Samplers::MemorySampler.supported_on_this_platform? || defined? JRuby
  end

end
