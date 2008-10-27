require File.expand_path(File.join(File.dirname(__FILE__),'/../test_helper'))

class NewRelic::ConfigTests < Test::Unit::TestCase
  
  def test_rails_config
    c = NewRelic::Config.instance
    assert_equal :test, c.app
    assert_equal false, c['enabled']
    c.local_env
  end
  
end
