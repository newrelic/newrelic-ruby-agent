require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/agent_logger'

class AgentLoggerTest < Test::Unit::TestCase
  def setup
    @config = {}
  end

  def test_initalizes_from_config
    @config[:log_file_path] = "log"
    @config[:log_file_name] = "testlog.log"

    inner_logger = stub()
    ::Logger.stubs(:new).with(any_parameters).returns(inner_logger)

    logger = NewRelic::Agent::AgentLogger.new(@config)
    assert_equal(inner_logger, logger.instance_variable_get(:@log))
  end

  def test_initalizes_from_override
    inner_log = mock()
    logger = NewRelic::Agent::AgentLogger.new(@config, "", {:log => inner_log})
    assert_equal inner_log, logger.instance_variable_get(:@log)
  end

  def test_forwards_debug_to_logger
    [:fatal, :error, :warn, :info, :debug].each do |level|
      inner_log = mock()
      inner_log.expects(level).with(any_parameters)

      logger = NewRelic::Agent::AgentLogger.new(@config, "", {:log => inner_log})

      logger.send(level, "Boo!")
    end
  end

  def test_dont_log_if_agent_not_enabled
    [:fatal, :error, :warn, :info, :debug].each do |level|
      ::Logger.any_instance.expects(level).never

      @config[:agent_enabled] = false
      logger = NewRelic::Agent::AgentLogger.new(@config)

      logger.send(level, "Boo")
    end
  end

  def test_log_to_stdout_and_warns_if_failed_on_create
    NewRelic::Agent::AgentLogger.any_instance.stubs(:find_or_create_file_path).returns(nil)

    stdout = stub()
    stdout.expects(:warn)
    ::Logger.stubs(:new).with(STDOUT).returns(stdout)

    logger = NewRelic::Agent::AgentLogger.new(@config)
    assert_equal stdout, logger.instance_variable_get(:@log)
  end

end
