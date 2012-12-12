require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/agent_logger'

class AgentLoggerTest < Test::Unit::TestCase
  def setup
    @config = {}
    @config[:log_file_path] = "log/"
    @config[:log_file_name] = "testlog.log"
  end

  def test_initalizes_from_config
    inner_logger = stub(:level=)
    ::Logger.stubs(:new).with(any_parameters).returns(inner_logger)

    logger = NewRelic::Agent::AgentLogger.new(@config)
    assert_equal(inner_logger, logger.instance_variable_get(:@log))
  end

  def test_initalizes_from_override
    inner_log = stub(:level=)
    logger = NewRelic::Agent::AgentLogger.new(@config, "", {:log => inner_log})
    assert_equal inner_log, logger.instance_variable_get(:@log)
  end

  def test_forwards_calls_to_logger
    [:fatal, :error, :warn, :info, :debug].each do |level|
      inner_log = stub(:level=)
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

  def test_maps_log_levels
    assert_equal Logger::FATAL, NewRelic::Agent::AgentLogger.log_level_for(:fatal)
    assert_equal Logger::ERROR, NewRelic::Agent::AgentLogger.log_level_for(:error)
    assert_equal Logger::WARN,  NewRelic::Agent::AgentLogger.log_level_for(:warn)
    assert_equal Logger::INFO,  NewRelic::Agent::AgentLogger.log_level_for(:info)
    assert_equal Logger::DEBUG, NewRelic::Agent::AgentLogger.log_level_for(:debug)

    assert_equal Logger::INFO, NewRelic::Agent::AgentLogger.log_level_for("")
    assert_equal Logger::INFO, NewRelic::Agent::AgentLogger.log_level_for(:unknown)
  end

  def test_sets_log_level
    inner_log = mock()
    inner_log.expects(:level=).with(Logger::DEBUG)
    @config[:log_level] = :debug

    logger = NewRelic::Agent::AgentLogger.new(@config, "", {:log => inner_log})
  end

  def test_log_to_stdout_and_warns_if_failed_on_create
    NewRelic::Agent::AgentLogger.any_instance.stubs(:find_or_create_file_path).returns(nil)

    stdout = stub(:level=)
    stdout.expects(:warn)
    ::Logger.stubs(:new).with(STDOUT).returns(stdout)

    logger = NewRelic::Agent::AgentLogger.new(@config)
    assert_equal stdout, logger.instance_variable_get(:@log)
  end

  def test_log_to_stdout_based_on_config
    @config[:log_file_path] = "STDOUT"

    stdout = stub(:level=)
    stdout.expects(:warn).never
    ::Logger.stubs(:new).with(STDOUT).returns(stdout)

    logger = NewRelic::Agent::AgentLogger.new(@config)
    assert_equal stdout, logger.instance_variable_get(:@log)
  end

end
