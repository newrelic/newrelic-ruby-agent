require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/agent_logger'

class AgentLoggerTest < Test::Unit::TestCase
  def setup
    @config = {
      :log_file_path => "log/",
      :log_file_name => "testlog.log",
      :log_level => :info,
    }
  end

  def test_initalizes_from_config
    override_logger = stub(:level=)
    ::Logger.stubs(:new).with(any_parameters).returns(override_logger)

    logger = NewRelic::Agent::AgentLogger.new(@config)
    assert_equal(override_logger, logger.instance_variable_get(:@log))
  end

  def test_initalizes_from_override
    override_logger = stub(:level=)
    logger = NewRelic::Agent::AgentLogger.new(@config, "", override_logger)
    assert_equal override_logger, logger.instance_variable_get(:@log)
  end

  def test_forwards_calls_to_logger
    [:fatal, :error, :warn, :info, :debug].each do |level|
      override_logger = stub(:level=)
      override_logger.expects(level).with(any_parameters)

      logger = NewRelic::Agent::AgentLogger.new(@config, "", override_logger)

      logger.send(level, "Boo!")
    end
  end


  def test_forwards_calls_to_logger_with_multiple_arguments
    [:fatal, :error, :warn, :info, :debug].each do |level|
      override_logger = stub(:level=)
      override_logger.expects(level).with("What\nup?")

      logger = NewRelic::Agent::AgentLogger.new(@config, "", override_logger)

      logger.send(level, "What", "up?")
    end
  end

  def test_passing_exceptions_gets_pretty_formatting
    caught = nil
    begin
      raise Exception.new("Boo!")
    rescue Exception => e
      caught = e
    end

    # Checking if it looks like message includes backtrace
    override_logger = stub(:level=)
    override_logger.expects(:debug).with {|msg| msg.include?("test_") }

    NewRelic::Agent::AgentLogger.new(@config, "", override_logger).debug(e)
  end

  def test_wont_log_if_agent_not_enabled
    ::Logger.stubs(:new).with("/dev/null").returns(stub(:level=)).at_least_once

    @config[:agent_enabled] = false
    logger = NewRelic::Agent::AgentLogger.new(@config)
  end

  def test_logs_to_nul_if_dev_null_not_there
    File.stubs(:exists?).with("/dev/null").returns(false)
    File.stubs(:exists?).with("NUL").returns(true)

    ::Logger.stubs(:new).with("NUL").returns(stub(:level=)).once

    @config[:agent_enabled] = false
    logger = NewRelic::Agent::AgentLogger.new(@config)
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
    override_logger = mock()
    override_logger.expects(:level=).with(Logger::DEBUG)
    @config[:log_level] = :debug

    logger = NewRelic::Agent::AgentLogger.new(@config, "", override_logger)
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

  def test_startup_purges_memory_logger
    [:fatal, :error, :warn, :info, :debug].each do |level|
      ::NewRelic::Agent::StartupLogger.instance.send(level, "boo!")

      override_logger = stub(:level=)
      override_logger.expects(level).with("boo!")

      NewRelic::Agent::AgentLogger.new(@config, "", override_logger)
    end
  end

  def test_format_message_allows_nil_backtrace
    override_logger = stub(:level=)
    override_logger.expects(:debug)

    logger = ::NewRelic::Agent::AgentLogger.new(@config, "", override_logger)

    logger.debug(Exception.new("Look Ma, no backtrace!"))
  end


  def test_logs_to_stdout_if_fails_on_file
    stdout = stub_everything()
    ::Logger.stubs(:new).with(STDOUT).returns(stdout)
    ::Logger.stubs(:new).with(instance_of(String)).raises(Errno::EACCES)

    logger = NewRelic::Agent::AgentLogger.new(@config, "")

    assert_equal stdout, logger.instance_variable_get(:@log)
  end
end
