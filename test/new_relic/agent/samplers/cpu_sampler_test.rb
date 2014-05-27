# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/samplers/cpu_sampler'

class NewRelic::Agent::Samplers::CpuSamplerTest < Minitest::Test

  def setup
    @original_jruby_version = JRUBY_VERSION if defined?(JRuby)
  end

  def teardown
    set_jruby_version_constant(@original_jruby_version) if defined?(JRuby)
  end

  def test_correcly_detecting_jruby_support_for_correct_cpu_sampling
    if defined?(JRuby)
      set_jruby_version_constant '1.6.8'
      refute_supported_on_platform

      set_jruby_version_constant '1.7.0'
      assert_supported_on_platform

      set_jruby_version_constant '1.7.4'
      assert_supported_on_platform
    else
      assert_supported_on_platform
    end
  end

  #
  # Helpers
  #

  def assert_supported_on_platform
    assert_equal NewRelic::Agent::Samplers::CpuSampler.supported_on_this_platform?, true, "should be supported on this platform"
  end

  def refute_supported_on_platform
    assert_equal NewRelic::Agent::Samplers::CpuSampler.supported_on_this_platform?, false, "should not be supported on this platform"
  end

  def set_jruby_version_constant(string)
    Object.send(:remove_const, 'JRUBY_VERSION') if defined?(JRUBY_VERSION)
    Object.const_set('JRUBY_VERSION', string)
  end

end
