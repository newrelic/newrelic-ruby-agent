require File.expand_path(File.join(File.dirname(__FILE__),'/../../test_helper'))
class NewRelic::Control::ConfigurationTest < Test::Unit::TestCase
  require 'new_relic/control/configuration'
  include NewRelic::Control::Configuration
  def test_license_key_defaults_to_env_variable
    ENV['NEWRELIC_LICENSE_KEY'] = nil
    self.expects(:fetch).with('license_key', nil)
    license_key

    ENV['NEWRELIC_LICENSE_KEY'] = "a string"
    self.expects(:fetch).with('license_key', 'a string')
    license_key
  end
  
    
end
