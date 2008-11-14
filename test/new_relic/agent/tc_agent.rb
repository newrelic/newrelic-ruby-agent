require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
##require 'new_relic/agent/agent'
##require 'new_relic/local_environment'
require 'net/http'

class AgentTests < ActiveSupport::TestCase
  
  attr_reader :agent
  
  # Fake out the agent to think mongrel is running
  def setup
    @agent = NewRelic::Agent.instance
    @agent.start :test, :test
  end
  
  # Remove the port method so it won't think mongrel
  # is available
  def teardown
    @agent.shutdown
    super
  end
  
  def test_public_apis
    begin
      NewRelic::Agent.set_sql_obfuscator(:unknown) do |sql|
        puts sql
      end
      fail
    rescue
      # ok
    end
    
    
    ignore_called = false
    NewRelic::Agent.ignore_error_filter do |e|
      ignore_called = true
      nil
    end
    
    NewRelic::Agent.agent.error_collector.notice_error('path', nil, {:x => 'y'}, ActionController::RoutingError.new("message"))
    
    assert ignore_called    
  end
  
  def test_startup_shutdown
    @agent.shutdown
    assert (not @agent.started?)
    @agent.start "ruby", "test1"
    assert @agent.started?
    @agent.shutdown
    @agent.start "ruby", "test2"
  end
  def test_setup_log_default
    assert @agent.log.instance_of?(Logger), @agent.log
    logfile = @agent.log.instance_eval { @logdev.filename }
    assert_match /\/log\/newrelic_agent\..*\.log$/,logfile
    @agent.shutdown
  end
  
  def test_info
    props = NewRelic::Config.instance.app_config_info
    list = props.assoc('Plugin List').last.sort
    assert_equal 4, (list & %w[active_merchant active_scaffold acts_as_list acts_as_state_machine ]).size, list.join("\n")
    assert_equal 'mysql', props.assoc('Database adapter').last
  end
  def test_version
    assert_match /\d\.\d\.\d+/, NewRelic::VERSION::STRING
  end
  
  def test_invoke_remote__ignore_non_200_results
    NewRelic::Agent::Agent.class_eval do
      public :invoke_remote
    end
    response_mock = mock()
    Net::HTTP.any_instance.stubs(:request).returns(response_mock)
    response_mock.stubs(:message).returns("bogus error")
    
    for code in %w[500 504 400 302 503] do 
      assert_raise NewRelic::Agent::IgnoreSilentlyException, "Ignore #{code}" do
        response_mock.stubs(:code).returns(code)
        NewRelic::Agent.agent.invoke_remote  :get_data_report_period, 0
      end
    end
  end
  def test_invoke_remote__throw_other_errors
    NewRelic::Agent::Agent.class_eval do
      public :invoke_remote
    end
    response_mock = Net::HTTPSuccess.new  nil, nil, nil
    response_mock.stubs(:body).returns("")
    Marshal.stubs(:load).raises(RuntimeError, "marshal issue")
    Net::HTTP.any_instance.stubs(:request).returns(response_mock)
    assert_raise RuntimeError do
      NewRelic::Agent.agent.invoke_remote  :get_data_report_period, 0xFEFE
    end
  end
end