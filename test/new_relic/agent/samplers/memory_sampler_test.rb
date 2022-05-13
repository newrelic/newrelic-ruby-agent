# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../../../test_helper'
require 'new_relic/agent/samplers/memory_sampler'

class NewRelic::Agent::Samplers::MemorySamplerTest < Minitest::Test
  def setup
    @stats_engine = NewRelic::Agent::StatsEngine.new
    NewRelic::Agent.instance.stubs(:stats_engine).returns(@stats_engine)
  end

  def test_memory__default
    stub_sampler_get_memory
    s = NewRelic::Agent::Samplers::MemorySampler.new
    s.poll
    s.poll
    s.poll
    assert_metrics_recorded "Memory/Physical" => {:call_count => 3, :total_call_time => 999}
  end

  def test_memory__linux
    return if RUBY_PLATFORM =~ /darwin/
    NewRelic::Agent::Samplers::MemorySampler.any_instance.stubs(:platform).returns 'linux'
    stub_sampler_get_memory
    s = NewRelic::Agent::Samplers::MemorySampler.new
    s.poll
    s.poll
    s.poll

    assert_metrics_recorded "Memory/Physical" => {:call_count => 3, :total_call_time => 999}
  end

  def test_memory__solaris
    return if defined? JRuby
    NewRelic::Agent::Samplers::MemorySampler.any_instance.stubs(:platform).returns 'solaris'
    NewRelic::Agent::Samplers::MemorySampler::ShellPS.any_instance.stubs(:get_memory).returns 999
    s = NewRelic::Agent::Samplers::MemorySampler.new
    s.poll
    assert_metrics_recorded "Memory/Physical" => {:call_count => 1, :total_call_time => 999}
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

  # leverage the 'uname' binary when running on JRuby
  def test_platform_uses_uname_for_jruby
    stubbed = 'MCP'
    NewRelic::Helper.stubs('run_command').with('uname -s').returns(stubbed)
    NewRelic::Agent::Samplers::MemorySampler.stub_const(:RUBY_PLATFORM, 'java') do
      platform = NewRelic::Agent::Samplers::MemorySampler.platform
      assert_equal platform, stubbed.downcase
    end
  end

  # if using 'uname' fails, use 'unknown' for the platform
  def test_platform_uses_unknown_if_uname_fails
    NewRelic::Helper.stubs('run_command').with('uname -s').raises(NewRelic::CommandRunFailedError)
    NewRelic::Agent::Samplers::MemorySampler.stub_const(:RUBY_PLATFORM, 'java') do
      platform = NewRelic::Agent::Samplers::MemorySampler.platform
      assert_equal platform, 'unknown'
    end
  end

  # use RUBY_PLATFORM for the platform for CRuby
  def test_platform_uses_ruby_platform
    stubbed = 'ENCOM OS-12'
    NewRelic::Agent::Samplers::MemorySampler.stub_const(:RUBY_PLATFORM, stubbed) do
      platform = NewRelic::Agent::Samplers::MemorySampler.platform
      assert_equal platform, stubbed.downcase
    end
  end

  def stub_sampler_get_memory
    if defined? JRuby
      NewRelic::Agent::Samplers::MemorySampler::JavaHeapSampler.any_instance.stubs(:get_memory).returns 333
    else
      NewRelic::Agent::Samplers::MemorySampler::ShellPS.any_instance.stubs(:get_memory).returns 333
      NewRelic::Agent::Samplers::MemorySampler::ProcStatus.any_instance.stubs(:get_memory).returns 333
    end
  end
end
