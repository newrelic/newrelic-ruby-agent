# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..', 'test_helper'))
class NewRelic::LocalEnvironmentTest < Minitest::Test

  def teardown
    NewRelic::Control.reset
  end

  def test_passenger
    with_constant_defined(:PhusionPassenger, Module.new) do
      NewRelic::Agent.reset_config
      e = NewRelic::LocalEnvironment.new
      assert_equal :passenger, e.discovered_dispatcher
      assert_equal :passenger, NewRelic::Agent.config[:dispatcher]

      with_config(:app_name => 'myapp') do
        e = NewRelic::LocalEnvironment.new
        assert_equal :passenger, e.discovered_dispatcher
      end
    end
  end
end
