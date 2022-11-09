# -*- ruby -*-
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/samplers/cpu_sampler'

class NewRelic::Agent::Samplers::CpuSamplerTest < Minitest::Test
  def setup
    @original_jruby_version = JRUBY_VERSION if defined?(JRuby)
  end

  def teardown
    clear_metrics!
    set_jruby_version_constant(@original_jruby_version) if defined?(JRuby)
  end

  def test_correctly_detecting_jruby_support_for_correct_cpu_sampling
    if defined?(JRuby)
      set_jruby_version_constant('1.6.8')

      refute_supported_on_platform

      set_jruby_version_constant('1.7.0')

      assert_supported_on_platform

      set_jruby_version_constant('1.7.4')

      assert_supported_on_platform
    else
      assert_supported_on_platform
    end
  end

  #
  # Helpers
  #

  def assert_supported_on_platform
    assert_predicate NewRelic::Agent::Samplers::CpuSampler, :supported_on_this_platform?, "should be supported on this platform"
  end

  def refute_supported_on_platform
    refute NewRelic::Agent::Samplers::CpuSampler.supported_on_this_platform?, "should not be supported on this platform"
  end

  def set_jruby_version_constant(string)
    Object.send(:remove_const, 'JRUBY_VERSION') if defined?(JRUBY_VERSION)
    Object.const_set(:JRUBY_VERSION, string)
  end

  def test_cpu_sampler_records_user_and_system_time
    timeinfo0 = mock
    timeinfo0.stubs(:utime).returns(10.0)
    timeinfo0.stubs(:stime).returns(5.0)

    timeinfo1 = mock
    timeinfo1.stubs(:utime).returns(14.0) # +5s
    timeinfo1.stubs(:stime).returns(7.0) # +2s

    elapsed = 10

    nr_freeze_process_time
    Process.stubs(:times).returns(timeinfo0, timeinfo1)
    NewRelic::Agent::SystemInfo.stubs(:num_logical_processors).returns(4)

    s = NewRelic::Agent::Samplers::CpuSampler.new # this calls poll
    advance_process_time(elapsed)
    s.poll

    assert_metrics_recorded({
      'CPU/User Time' => {:call_count => 1, :total_call_time => 4.0},
      'CPU/System Time' => {:call_count => 1, :total_call_time => 2.0},
      # (4s user time)   / ((10s elapsed time) * 4 cpus) = 0.1
      'CPU/User/Utilization' => {:call_count => 1, :total_call_time => 0.1},
      # (2s system time) / ((10s elapsed time) * 4 cpus) = 0.05
      'CPU/System/Utilization' => {:call_count => 1, :total_call_time => 0.05}
    })
  end

  def test_cpu_sampler_doesnt_return_negative_user_and_system_utilization_values
    timeinfo0 = mock
    timeinfo0.stubs(:utime).returns(10.0)
    timeinfo0.stubs(:stime).returns(5.0)

    timeinfo1 = mock
    timeinfo1.stubs(:utime).returns(0.0)
    timeinfo1.stubs(:stime).returns(0.0)

    nr_freeze_process_time
    Process.stubs(:times).returns(timeinfo0, timeinfo1)

    s = NewRelic::Agent::Samplers::CpuSampler.new # this calls poll
    s.poll

    assert_metrics_not_recorded([
      'CPU/User/Utilization',
      'CPU/System/Utilization'
    ])
  end
end
