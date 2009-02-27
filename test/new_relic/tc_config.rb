require File.expand_path(File.join(File.dirname(__FILE__),'/../test_helper'))

module NewRelic
  class Config
    public :log_file_name
  end
end

class NewRelic::ConfigTests < Test::Unit::TestCase

  attr_reader :c
  
  def setup
    NewRelic::Agent.manual_start
    @c =  NewRelic::Config.instance
  end
  
  def test_test_config
    assert_equal :rails, c.app
    assert_equal :test, c.framework
    assert_match /test/i, c.dispatcher_instance_id
    assert_equal nil, c.dispatcher
    
    assert_equal false, c['enabled']
    c.local_env
  end

  def test_info
    props = NewRelic::Config.instance.app_config_info
    list = props.assoc('Plugin List').last.sort
    assert_not_nil list # can't really guess what might be in here.  
    assert_match /jdbc|postgres|mysql|sqlite/, props.assoc('Database adapter').last
  end

  def test_config_yaml_erb
    assert_equal 'heyheyhey', c['erb_value']
    assert_equal '', c['message']
    assert_equal '', c['license_key']
  end
  
  def test_config_booleans
    assert_equal c['tval'], true
    assert_equal c['fval'], false
    assert_nil c['not_in_yaml_val']
    assert_equal c['yval'], true 
    assert_equal c['sval'], 'sure'
  end
  def test_config_apdex
    assert_equal 1.1, c['apdex_t']
  end
  def test_log_file_name
    assert_match /newrelic_agent.log$/, c.instance_variable_get('@log_file')
  end
  
end
