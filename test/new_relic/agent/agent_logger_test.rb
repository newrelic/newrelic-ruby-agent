# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/agent_logger'
require 'new_relic/agent/null_logger'

class ArrayLogDevice
  def initialize( array=[] )
    @array = array
  end
  attr_reader :array

  def write( message )
    @array << message
  end

  def close; end
end


class AgentLoggerTest < Test::Unit::TestCase

  LEVELS = [:fatal, :error, :warn, :info, :debug]

  def setup
    @config = {
      :log_file_path => "log/",
      :log_file_name => "testlog.log",
      :log_level => :info,
    }
  end


  #
  # Tests
  #

  def test_initalizes_from_config
    logger = NewRelic::Agent::AgentLogger.new(@config)

    wrapped_logger = logger.instance_variable_get( :@log )
    logdev = wrapped_logger.instance_variable_get( :@logdev )
    expected_logpath = File.expand_path( @config[:log_file_path] + @config[:log_file_name] )

    assert_kind_of( Logger, wrapped_logger )
    assert_kind_of( File, logdev.dev )
    assert_equal( expected_logpath, logdev.filename )
  end

  def test_initalizes_from_override
    override_logger = Logger.new( '/dev/null' )
    logger = NewRelic::Agent::AgentLogger.new(@config, "", override_logger)
    assert_equal override_logger, logger.instance_variable_get(:@log)
  end


  def test_forwards_calls_to_logger
    logdev = ArrayLogDevice.new
    override_logger = Logger.new( logdev )
    logger = NewRelic::Agent::AgentLogger.new(@config, "", override_logger)

    LEVELS.each do |level|
      logger.send(level, "Boo!")
    end

    assert_equal 4, logdev.array.length # No DEBUG

    assert_match( /FATAL/, logdev.array[0] )
    assert_match( /ERROR/, logdev.array[1] )
    assert_match( /WARN/,  logdev.array[2] )
    assert_match( /INFO/,  logdev.array[3] )
  end


  def test_forwards_calls_to_logger_with_multiple_arguments
    logdev = ArrayLogDevice.new
    override_logger = Logger.new( logdev )
    logger = NewRelic::Agent::AgentLogger.new(@config, "", override_logger)

    LEVELS.each do |level|
      logger.send(level, "What", "up?")
    end

    assert_equal 8, logdev.array.length # No DEBUG, two per level

    assert_match( /FATAL/, logdev.array[0] )
    assert_match( /FATAL/, logdev.array[1] )
    assert_match( /ERROR/, logdev.array[2] )
    assert_match( /ERROR/, logdev.array[3] )
    assert_match( /WARN/,  logdev.array[4] )
    assert_match( /WARN/,  logdev.array[5] )
    assert_match( /INFO/,  logdev.array[6] )
    assert_match( /INFO/,  logdev.array[7] )
  end

  def test_wont_log_if_agent_not_enabled
    @config[:agent_enabled] = false
    logger = NewRelic::Agent::AgentLogger.new(@config)
    assert_nothing_raised do
      logger.warn('hi there')
    end

    assert_kind_of NewRelic::Agent::NullLogger, logger.instance_variable_get( :@log )
  end

  def test_does_not_touch_dev_null
    Logger.expects(:new).with('/dev/null').never
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
    @config[:log_level] = :debug

    override_logger = Logger.new( $stderr )
    override_logger.level = Logger::FATAL

    logger = NewRelic::Agent::AgentLogger.new(@config, "", override_logger)

    assert_equal Logger::DEBUG, override_logger.level
  end

  def test_log_to_stdout_and_warns_if_failed_on_create
      Dir.stubs(:mkdir).returns(nil)
      config = @config.merge( :log_file_path => '/someplace/non/existant' )

    logger = with_squelched_stdout do
      NewRelic::Agent::AgentLogger.new(config)
    end

    wrapped_logger = logger.instance_variable_get(:@log)
    logdev = wrapped_logger.instance_variable_get(:@logdev)

    assert_equal $stdout, logdev.dev
  end

  def test_log_to_stdout_based_on_config
    @config[:log_file_path] = "STDOUT"

    logger = NewRelic::Agent::AgentLogger.new(@config)
    wrapped_logger = logger.instance_variable_get(:@log)
    logdev = wrapped_logger.instance_variable_get(:@logdev)

    assert_equal $stdout, logdev.dev
  end

  def test_startup_purges_memory_logger
    LEVELS.each do |level|
      ::NewRelic::Agent::StartupLogger.instance.send(level, "boo!")
    end

    logdev = ArrayLogDevice.new
    override_logger = Logger.new( logdev )
    logger = NewRelic::Agent::AgentLogger.new(@config, "", override_logger)

    assert_equal 4, logdev.array.length # No DEBUG

    assert_match( /FATAL/, logdev.array[0] )
    assert_match( /ERROR/, logdev.array[1] )
    assert_match( /WARN/,  logdev.array[2] )
    assert_match( /INFO/,  logdev.array[3] )
  end

  def test_passing_exceptions_only_logs_the_message_at_levels_higher_than_debug
    logdev = ArrayLogDevice.new
    override_logger = Logger.new( logdev )
    logger = NewRelic::Agent::AgentLogger.new(@config, "", override_logger)

    begin
      raise "Something bad happened"
    rescue => err
      logger.error( err )
    end

    assert_equal 1, logdev.array.length
    assert_match( /ERROR : RuntimeError: Something bad happened/i, logdev.array[0] )
  end

  def test_passing_exceptions_logs_the_backtrace_at_debug_level
    config = @config.merge(:log_level => :debug)

    logdev = ArrayLogDevice.new
    override_logger = Logger.new( logdev )
    logger = NewRelic::Agent::AgentLogger.new(config, "", override_logger)

    begin
      raise "Something bad happened"
    rescue => err
      logger.error( err )
    end

    assert_equal 2, logdev.array.length
    assert_match( /ERROR : RuntimeError: Something bad happened/i, logdev.array[0] )
    assert_match( /DEBUG : Debugging backtrace:\n.*test_passing_exceptions/i,
                  logdev.array[1] )
  end

  def test_format_message_allows_nil_backtrace
    config = @config.merge(:log_level => :debug)

    logdev = ArrayLogDevice.new
    override_logger = Logger.new( logdev )
    logger = NewRelic::Agent::AgentLogger.new(config, "", override_logger)

    e = Exception.new("Look Ma, no backtrace!")
    assert_nil(e.backtrace)
    logger.error(e)

    assert_equal 2, logdev.array.length
    assert_match( /ERROR : Exception: Look Ma, no backtrace!/i, logdev.array[0] )
    assert_match( /DEBUG : No backtrace available./, logdev.array[1])
  end

  def test_log_exception_logs_backtrace_at_same_level_as_message_by_default
    logdev = ArrayLogDevice.new
    override_logger = Logger.new(logdev)
    logger = NewRelic::Agent::AgentLogger.new(@config, "", override_logger)

    e = Exception.new("howdy")
    e.set_backtrace(["wiggle", "wobble", "topple"])

    logger.log_exception(:info, e)

    assert_match(/INFO : Exception: howdy/i, logdev.array[0])
    assert_match(/INFO : Debugging backtrace:\n.*wiggle\s+wobble\s+topple/,
                  logdev.array[1])
  end

  def test_log_exception_logs_backtrace_at_explicitly_specified_level
    logdev = ArrayLogDevice.new
    override_logger = Logger.new(logdev)
    logger = NewRelic::Agent::AgentLogger.new(@config, "", override_logger)

    e = Exception.new("howdy")
    e.set_backtrace(["wiggle", "wobble", "topple"])

    logger.log_exception(:warn, e, :info)

    assert_match(/WARN : Exception: howdy/i, logdev.array[0])
    assert_match(/INFO : Debugging backtrace:\n.*wiggle\s+wobble\s+topple/,
                  logdev.array[1])
  end

  def test_logs_to_stdout_if_fails_on_file
    Logger::LogDevice.any_instance.stubs(:open).raises(Errno::EACCES)

    logger = with_squelched_stdout do
      NewRelic::Agent::AgentLogger.new(@config, "")
    end

    wrapped_logger = logger.instance_variable_get(:@log)
    logdev = wrapped_logger.instance_variable_get(:@logdev)

    assert_equal $stdout, logdev.dev
  end

  def test_null_logger_works_with_impolite_gems_that_add_stuff_to_kernel
    Kernel.module_eval do
      def debug; end
    end

    logger = NewRelic::Agent::AgentLogger.new(@config.merge(:agent_enabled => false))
    assert_nothing_raised do
      logger.debug('hi!')
    end
  ensure
    Kernel.module_eval do
      remove_method :debug
    end
  end



  #
  # Helpers
  #

  def with_squelched_stdout
    orig = $stdout.dup
    $stdout.reopen( '/dev/null' )
    yield
  ensure
    $stdout.reopen( orig )
  end

end
