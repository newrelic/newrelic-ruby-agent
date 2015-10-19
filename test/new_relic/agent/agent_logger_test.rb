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


class AgentLoggerTest < Minitest::Test

  LEVELS = [:fatal, :error, :warn, :info, :debug]

  def setup
    NewRelic::Agent.config.add_config_for_testing(
      :log_file_path => "log/",
      :log_file_name => "testlog.log",
      :log_level     => :info)
  end

  def teardown
    NewRelic::Agent.config.reset_to_defaults
    NewRelic::Agent::Hostname.instance_variable_set(:@hostname, nil)
  end


  #
  # Tests
  #

  def test_initalizes_from_config
    logger = NewRelic::Agent::AgentLogger.new

    wrapped_logger = logger.instance_variable_get( :@log )
    logdev = wrapped_logger.instance_variable_get( :@logdev )
    expected_logpath = File.expand_path( NewRelic::Agent.config[:log_file_path] + NewRelic::Agent.config[:log_file_name] )

    assert_kind_of( Logger, wrapped_logger )
    assert_kind_of( File, logdev.dev )
    assert_equal( expected_logpath, logdev.filename )
  end

  def test_initalizes_from_override
    override_logger = Logger.new( '/dev/null' )
    logger = NewRelic::Agent::AgentLogger.new("", override_logger)
    assert_equal override_logger, logger.instance_variable_get(:@log)
  end

  def test_forwards_calls_to_logger
    logger = create_basic_logger

    LEVELS.each do |level|
      logger.send(level, "Boo!")
    end

    assert_logged(/FATAL/,
                  /ERROR/,
                  /WARN/,
                  /INFO/) # No DEBUG
  end

  def test_forwards_calls_to_logger_with_multiple_arguments
    logger = create_basic_logger

    LEVELS.each do |level|
      logger.send(level, "What", "up?")
    end

    assert_logged(/FATAL/, /FATAL/,
                  /ERROR/, /ERROR/,
                  /WARN/,  /WARN/,
                  /INFO/,  /INFO/) # No DEBUG
  end

  def test_forwards_calls_to_logger_once
    logger = create_basic_logger

    LEVELS.each do |level|
      logger.send(:log_once, level, :special_key, "Special!")
    end

    assert_logged(/Special/)
  end

  def test_wont_log_if_agent_not_enabled
    with_config(:agent_enabled => false) do
      logger = NewRelic::Agent::AgentLogger.new
      logger.warn('hi there')

      assert_kind_of NewRelic::Agent::NullLogger, logger.instance_variable_get( :@log )
    end
  end

  def test_consider_null_logger_a_startup_logger
    with_config(:agent_enabled => false) do
      logger = NewRelic::Agent::AgentLogger.new
      assert logger.is_startup_logger?
    end
  end

  def test_consider_any_other_logger_not_a_startup_logger
    logger = NewRelic::Agent::AgentLogger.new
    refute logger.is_startup_logger?
  end

  def test_does_not_touch_dev_null
    Logger.expects(:new).with('/dev/null').never
    with_config(:agent_enabled => false) do
      NewRelic::Agent::AgentLogger.new
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
    with_config(:log_level => :debug) do
      override_logger = Logger.new( $stderr )
      override_logger.level = Logger::FATAL

      NewRelic::Agent::AgentLogger.new("", override_logger)

      assert_equal Logger::DEBUG, override_logger.level
    end
  end

  def test_log_to_stdout_and_warns_if_failed_on_create
    Dir.stubs(:mkdir).returns(nil)

    with_config(:log_file_path => '/someplace/nonexistent') do
      logger = with_squelched_stdout do
        NewRelic::Agent::AgentLogger.new
      end

      wrapped_logger = logger.instance_variable_get(:@log)
      logdev = wrapped_logger.instance_variable_get(:@logdev)

      assert_equal $stdout, logdev.dev
    end
  end

  def test_log_to_stdout_based_on_config
    with_config(:log_file_path => 'STDOUT') do
      logger = NewRelic::Agent::AgentLogger.new
      wrapped_logger = logger.instance_variable_get(:@log)
      logdev = wrapped_logger.instance_variable_get(:@logdev)

      assert_equal $stdout, logdev.dev
    end
  end

  def test_startup_purges_memory_logger
    LEVELS.each do |level|
      ::NewRelic::Agent::StartupLogger.instance.send(level, "boo!")
    end

    create_basic_logger

    assert_logged(/FATAL/,
                  /ERROR/,
                  /WARN/,
                  /INFO/) # No DEBUG
  end

  def test_passing_exceptions_only_logs_the_message_at_levels_higher_than_debug
    logger = create_basic_logger

    begin
      raise "Something bad happened"
    rescue => err
      logger.error( err )
    end

    assert_logged(/ERROR : RuntimeError: Something bad happened/i)
  end

  def test_passing_exceptions_logs_the_backtrace_at_debug_level
    with_config(:log_level => :debug) do
      logger = create_basic_logger

      begin
        raise "Something bad happened"
      rescue => err
        logger.error( err )
      end

      assert_logged(/ERROR : RuntimeError: Something bad happened/i,
                    /DEBUG : Debugging backtrace:\n.*test_passing_exceptions/i)
    end
  end

  def test_default_format_contains_full_year
    with_config(:log_level => :debug) do
      logger = create_basic_logger

      logger.info("The nice thing about standards is that you have so many to choose from. -- ast")
      assert_logged(/#{Date.today.strftime("%Y-%m-%d")}/)
    end
  end

  def test_format_message_allows_nil_backtrace
    with_config(:log_level => :debug) do
      logger = create_basic_logger

      e = Exception.new("Look Ma, no backtrace!")
      assert_nil(e.backtrace)
      logger.error(e)

      assert_logged(/ERROR : Exception: Look Ma, no backtrace!/i,
                    /DEBUG : No backtrace available./)
    end
  end

  def test_log_exception_logs_backtrace_at_same_level_as_message_by_default
    logger = create_basic_logger

    e = Exception.new("howdy")
    e.set_backtrace(["wiggle", "wobble", "topple"])

    logger.log_exception(:info, e)

    assert_logged(/INFO : Exception: howdy/i,
                  /INFO : Debugging backtrace:\n.*wiggle\s+wobble\s+topple/)
  end

  def test_log_exception_logs_backtrace_at_explicitly_specified_level
    logger = create_basic_logger

    e = Exception.new("howdy")
    e.set_backtrace(["wiggle", "wobble", "topple"])

    logger.log_exception(:warn, e, :info)

    assert_logged(/WARN : Exception: howdy/i,
                  /INFO : Debugging backtrace:\n.*wiggle\s+wobble\s+topple/)
  end

  def recursion_is_an_antipattern
    recursion_is_an_antipattern
  end

  def test_log_exception_gets_backtrace_for_system_stack_error
    # This facility compensates for poor SystemStackError traces on MRI.
    # JRuby and Rubinius raise errors with good backtraces, so skip this test.
    return if jruby? || rubinius?

    logger = create_basic_logger

    begin
      recursion_is_an_antipattern
    rescue SystemStackError => e
      logger.log_exception(:error, e)
    end

    assert_logged(/ERROR : /,
                  /ERROR : Debugging backtrace:\n.*#{__method__}/)
  end

  def test_logs_to_stdout_if_fails_on_file
    Logger::LogDevice.any_instance.stubs(:open).raises(Errno::EACCES)

    logger = with_squelched_stdout do
      NewRelic::Agent::AgentLogger.new
    end

    wrapped_logger = logger.instance_variable_get(:@log)
    logdev = wrapped_logger.instance_variable_get(:@logdev)

    assert_equal $stdout, logdev.dev
  end

  def test_null_logger_works_with_impolite_gems_that_add_stuff_to_kernel
    Kernel.module_eval do
      def debug; end
    end

    logger = NewRelic::Agent::AgentLogger.new
    with_config(:agent_enabled => false) do
      logger.debug('hi!')
    end
  ensure
    Kernel.module_eval do
      remove_method :debug
    end
  end

  def test_should_cache_hostname
    NewRelic::Agent::Hostname.instance_variable_set(:@hostname, nil)
    Socket.expects(:gethostname).once.returns('cachey-mccaherson')
    logger = create_basic_logger
    logger.warn("one")
    logger.warn("two")
    logger.warn("three")
    host_regex = /cachey-mccaherson/
    assert_logged(host_regex, host_regex, host_regex)
  end

  def test_should_not_evaluate_blocks_unless_log_level_is_high_enough
    with_config(:log_level => 'warn') do
      logger = create_basic_logger

      block_was_evalutated = false
      logger.info do
        block_was_evalutated = true
      end

      refute block_was_evalutated
    end
  end

  def test_should_allow_blocks_that_return_a_single_string
    logger = create_basic_logger
    logger.warn { "Surely you jest!" }

    assert_logged(/WARN : Surely you jest!/)
  end

  def test_should_allow_blocks_that_return_an_array
    logger = create_basic_logger
    logger.warn do
      ["You must be joking!", "You can't be serious!"]
    end

    assert_logged(
      /WARN : You must be joking!/,
      /WARN : You can't be serious!/
    )
  end

  def test_can_overwrite_log_formatter
    log_message   = 'How are you?'
    log_formatter = Proc.new { |s, t, p, m| m.reverse }

    logger = create_basic_logger
    logger.log_formatter = log_formatter
    logger.warn log_message

    assert_logged log_message.reverse
  end

  def test_clear_already_logged
    logger = create_basic_logger
    logger.log_once(:warn, :positive, "thoughts")
    logger.log_once(:warn, :positive, "thoughts")

    assert_logged "thoughts"

    logger.clear_already_logged
    logger.log_once(:warn, :positive, "thoughts")

    assert_logged "thoughts", "thoughts"
  end

  #
  # Helpers
  #

  def logged_lines
    @logdev.array
  end

  def create_basic_logger
    @logdev = ArrayLogDevice.new
    override_logger = Logger.new(@logdev)
    NewRelic::Agent::AgentLogger.new("", override_logger)
  end

  def with_squelched_stdout
    orig = $stdout.dup
    $stdout.reopen( '/dev/null' )
    yield
  ensure
    $stdout.reopen( orig )
  end

  def assert_logged(*args)
    assert_equal(args.length, logged_lines.length, "Unexpected log length #{logged_lines}")
    logged_lines.each_with_index do |line, index|
      assert_match(args[index], line, "Missing match for #{args[index]}")
    end
  end
end
