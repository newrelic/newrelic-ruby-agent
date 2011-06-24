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
  
  def test_log_file_path_uses_default_if_not_set
    assert_equal(File.join(Rails.root, 'log'),
                 NewRelic::Control.instance.log_file_path)
  end

  def test_log_file_path_uses_given_value
    NewRelic::Control.instance['log_file_path'] = '/lerg'
    assert_equal '/lerg', NewRelic::Control.instance.log_file_path
  end
end
