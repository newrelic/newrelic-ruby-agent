# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..', 'test_helper'))

# Test logic around detecting or configuring framework
class FrameworkTest < Minitest::Test

  def setup

    # muck with this constant which forces the agent to load the
    # NewRelic::Control::Frameworks::Test control so we can test the logic used
    # to load the appropriate control object.
    @old_newrelic_test_const = ::NewRelic::TEST
    ::NewRelic.send(:remove_const, :TEST)

    NewRelic::Agent.shutdown
    NewRelic::Agent.reset_config

    # don't bomb out trying to load frameworks that don't exist.
    NewRelic::Control.stubs(:new_instance).returns(stub :init_plugin => nil)
  end

  def teardown
    # Put things back how we found them
    ::NewRelic.send(:const_set, :TEST,  @old_newrelic_test_const)
    NewRelic::Agent.reset_config
  end

  def test_detects_framework_via_loaded_libraries
    class << self
      module ::Merb
        module Plugins
        end
      end
    end
    assert_equal :merb, NewRelic::Agent.config[:framework]
  ensure
    Object.send(:remove_const, :Merb)
  end

  def test_detects_framework_via_ENV_NEW_RELIC_FRAMEWORK
    ENV['NEW_RELIC_FRAMEWORK'] = "foobared"
    NewRelic::Agent.reset_config
    assert_equal :foobared, NewRelic::Agent.config[:framework]
  ensure
    ENV['NEW_RELIC_FRAMEWORK'] = nil
  end

  def test_detects_framework_via_ENV_NEWRELIC_FRAMEWORK
    ENV['NEWRELIC_FRAMEWORK'] = "bazbang"
    NewRelic::Agent.reset_config
    assert_equal :bazbang, NewRelic::Agent.config[:framework]
  ensure
    ENV['NEWRELIC_FRAMEWORK'] = nil
  end
end
