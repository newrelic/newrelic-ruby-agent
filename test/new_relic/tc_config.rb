require File.expand_path(File.join(File.dirname(__FILE__),'/../test_helper'))


module NewRelic
  class Config
    public :log_file_name
  end
end

class NewRelic::ConfigTests < Test::Unit::TestCase
  
  def test_rails_config
    c = NewRelic::Config.instance
    assert_equal :rails, c.app
    assert_equal false, c['enabled']
    c.local_env
  end

  def test_config_yaml_erb
    c = NewRelic::Config.instance
    assert_equal 'heyheyhey', c['erb_value']
    assert_equal '', c['message']
    assert_equal '', c['license_key']
  end
  
  def test_log_file_name
    c = NewRelic::Config.instance
    
    assert_equal "newrelic_agent.3000.log", c.log_file_name("3000")
    assert_equal "newrelic_agent.passenger_redmine-0.7.log", c.log_file_name("passenger:redmine-0.7")
    assert_equal "newrelic_agent._tmp_test_1.log", c.log_file_name("/tmp/test/1")
    assert_equal "newrelic_agent.c__foo_bar_long_gone__yes_.log", c.log_file_name("c:/foo/bar long gone?/yes!")
    assert_equal "newrelic_agent..._tmp_pipes.log", c.log_file_name("..\\tmp\\pipes")
  end
  
end
