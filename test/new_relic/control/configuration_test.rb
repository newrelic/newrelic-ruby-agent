require File.expand_path(File.join(File.dirname(__FILE__),'/../../test_helper'))

class NewRelic::Control::ConfigurationTest < Test::Unit::TestCase
  require 'new_relic/control/configuration'
  include NewRelic::Control::Configuration
  
  def setup
    # The log stuff is memoized so let's clear it each time.
    NewRelic::Control.instance.instance_variable_set '@log_path', nil
    NewRelic::Control.instance.instance_variable_set '@log_file', nil
    @root = ::Rails::VERSION::MAJOR == 3 ? Rails.root : RAILS_ROOT
  end

  def test_log_path_uses_default_if_not_set
    NewRelic::Control.instance.setup_log
    assert_match(/log\/newrelic_agent.log$/,
                 NewRelic::Control.instance.log_file)
  end

  def test_log_file_path_uses_given_value
    Dir.stubs(:mkdir).returns(true)
    with_config(:log_file_path => 'lerg') do
      NewRelic::Control.instance.setup_log
      assert_match(/\/lerg\/newrelic_agent.log$/,
                   NewRelic::Control.instance.log_file)
    end
  end

  def test_install_browser_monitoring
    require(File.expand_path(File.join(File.dirname(__FILE__),
                         '/../../../lib/new_relic/rack/browser_monitoring')))
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
end
