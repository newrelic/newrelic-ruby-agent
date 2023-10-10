# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'

class NewRelic::Control::Frameworks::RailsTest < Minitest::Test
  def setup
    reset_installed_instance_variable
  end

  def teardown
    reset_installed_instance_variable
  end

  def test_install_browser_monitoring
    require 'new_relic/rack/browser_monitoring'
    middleware = stub('middleware config')
    config = stub('rails config', :middleware => middleware)
    middleware.expects(:use).with(NewRelic::Rack::BrowserMonitoring)
    with_config(:'browser_monitoring.auto_instrument' => true) do
      NewRelic::Control.instance.install_browser_monitoring(config)
    end
  end

  def test_install_browser_monitoring_should_not_install_when_not_configured
    middleware = stub('middleware config')
    config = stub('rails config', :middleware => middleware)
    middleware.expects(:use).never
    set_installed_instance_variable
    with_config(:'browser_monitoring.auto_instrument' => false) do
      NewRelic::Control.instance.install_browser_monitoring(config)
    end
  end

  private

  def reset_installed_instance_variable
    return unless NewRelic::Control::Frameworks::Rails::INSTALLED_SINGLETON.instance_variable_defined?(
      NewRelic::Control::Frameworks::Rails::INSTALLED
    )

    NewRelic::Control::Frameworks::Rails::INSTALLED_SINGLETON.remove_instance_variable(
      NewRelic::Control::Frameworks::Rails::INSTALLED
    )
  end

  def set_installed_instance_variable
    NewRelic::Control::Frameworks::Rails::INSTALLED_SINGLETON.instance_variable_set(
      NewRelic::Control::Frameworks::Rails::INSTALLED, true
    )
  end
end
