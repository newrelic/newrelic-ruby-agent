require File.expand_path(File.join(File.dirname(__FILE__),'/../../../test_helper'))

class NewRelic::Control::Frameworks::RailsTest < Test::Unit::TestCase
  def test_install_browser_monitoring
    require(File.expand_path(File.join(File.dirname(__FILE__),
                         '/../../../../lib/new_relic/rack/browser_monitoring')))
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
