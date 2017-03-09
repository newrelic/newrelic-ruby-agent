# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'/../../../test_helper'))

class NewRelic::Control::Frameworks::RailsTest < Minitest::Test
  def test_install_browser_monitoring
    require 'new_relic/rack/browser_monitoring'
    middleware = stub('middleware config')
    config = stub('rails config', :middleware => middleware)
    middleware.expects(:use).with(NewRelic::Rack::BrowserMonitoring)
    NewRelic::Control.instance.instance_eval { @browser_monitoring_installed = false }
    with_config(:'browser_monitoring.auto_instrument' => true) do
      NewRelic::Control.instance.install_browser_monitoring(config)
    end
  end

  def test_install_browser_monitoring_should_not_install_when_not_configured
    middleware = stub('middleware config')
    config = stub('rails config', :middleware => middleware)
    middleware.expects(:use).never
    NewRelic::Control.instance.instance_eval { @browser_monitoring_installed = false }

    with_config(:'browser_monitoring.auto_instrument' => false) do
      NewRelic::Control.instance.install_browser_monitoring(config)
    end
  end

  def test_new_relic_env_should_be_used_when_specified_in_rails
    with_constant_defined(:RAILS_ENV, "test") do
      with_environment("NEW_RELIC_ENV" => "my_env") do
        local_env = mock('local env')
        assert_equal "my_env", NewRelic::Control::Frameworks::Rails.new(local_env).env
        assert_equal "my_env", NewRelic::Control::Frameworks::Rails3.new(local_env).env
        assert_equal "my_env", NewRelic::Control::Frameworks::Rails4.new(local_env).env
        assert_equal "my_env", NewRelic::Control::Frameworks::Rails5.new(local_env).env
      end
    end
  end
end
