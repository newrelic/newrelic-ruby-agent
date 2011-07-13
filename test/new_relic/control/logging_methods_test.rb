require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))
require 'new_relic/control/logging_methods'
require 'fileutils'

class BaseLoggingMethods
  # stub class to enable testing of the module
  include NewRelic::Control::LoggingMethods
  def root; "."; end
end

class NewRelic::Control::LoggingMethodsTest < Test::Unit::TestCase
  def setup
    @base = BaseLoggingMethods.new
    super
  end

  def test_log_basic
    mock_logger = mock('logger')
    @base.instance_eval { @log = mock_logger }
    assert_equal mock_logger, @base.log
  end

  def test_log_no_log
    log = @base.log
    assert_equal Logger, log.class
    assert_equal Logger::INFO, log.level
    # have to root around in the logger for the logdev
    assert_equal STDOUT, log.instance_eval { @logdev }.dev
  end

  def test_logbang_basic
    @base.expects(:should_log?).returns(true)
    @base.expects(:to_stdout).with('whee')
    @base.instance_eval { @log = nil }
    @base.log!('whee')
  end

  def test_logbang_should_not_log
    @base.expects(:should_log?).returns(false)
    assert_equal nil, @base.log!('whee')
  end

  def test_logbang_with_log
    @base.expects(:should_log?).returns(true)
    @base.expects(:to_stdout).with('whee')
    fake_logger = mock('log')
    fake_logger.expects(:send).with(:info, 'whee')
    @base.instance_eval { @log = fake_logger }
    @base.log!('whee')
  end

  def test_should_log_no_settings
    @base.instance_eval { @settings = nil }
    assert !@base.should_log?
  end

  def test_should_log_agent_disabled
    @base.instance_eval { @settings = true }
    @base.expects(:agent_enabled?).returns(false)
    assert !@base.should_log?
  end

  def test_should_log_agent_enabled
    @base.instance_eval { @settings = true }
    @base.expects(:agent_enabled?).returns(true)
    assert @base.should_log?
  end

  def test_set_log_level_base
    fake_logger = mock('logger')
    # bad configuration
    @base.expects(:fetch).with('log_level', 'info').returns('whee')
    fake_logger.expects(:level=).with(Logger::INFO)
    assert_equal fake_logger, @base.set_log_level!(fake_logger)
  end

  def test_set_log_level_with_each_level
    fake_logger = mock('logger')
    %w[debug info warn error fatal].each do |level|
      @base.expects(:fetch).with('log_level', 'info').returns(level)
      fake_logger.expects(:level=).with(Logger.const_get(level.upcase))
      assert_equal fake_logger, @base.set_log_level!(fake_logger)
    end
  end

  def test_set_log_format
    fake_logger = Object.new
    assert !fake_logger.respond_to?(:format_message)
    assert_equal fake_logger, @base.set_log_format!(fake_logger)
    assert fake_logger.respond_to?(:format_message)
  end

  def test_setup_log_file_not_exist
    @base.expects(:log_path).returns('logpath')
    @base.expects(:log_file_name).returns('logfilename')
    fake_logger = mock('logger')
    @base.expects(:log).returns(fake_logger)
    @base.setup_log
    assert_equal nil, @base.instance_eval { @log }
    assert_equal 'logpath/logfilename', @base.instance_eval { @log_file }
  end

  def test_setup_log_existing_file
    fake_logger = mock('logger')
    Logger.expects(:new).with('logpath/logfilename').returns(fake_logger)
    @base.expects(:log_path).returns('logpath')
    @base.expects(:log_file_name).returns('logfilename')
    @base.expects(:set_log_format!).with(fake_logger)
    @base.expects(:set_log_level!).with(fake_logger)
    assert_equal fake_logger, @base.setup_log
    assert_equal fake_logger, @base.instance_eval { @log }
    assert_equal 'logpath/logfilename', @base.instance_eval { @log_file }
  end

  def test_to_stdout
    STDOUT.expects(:puts).with('** [NewRelic] whee')
    @base.to_stdout('whee')
  end

  def test_log_path_exists
    @base.instance_eval { @log_path = 'logpath' }
    assert_equal 'logpath', @base.log_path
  end

  def test_log_path_path_exists
    @base.instance_eval { @log_path = nil }
    @base.expects(:fetch).with('log_file_path', 'log').returns('log')
    assert File.directory?('log')
    assert_equal File.expand_path('log'), @base.log_path
  end

  def test_log_path_path_created
    path = File.expand_path('tmp/log_path_test')
    @base.instance_eval { @log_path = nil }
    @base.expects(:fetch).with('log_file_path', 'log').returns('tmp/log_path_test')
    assert !File.directory?(path) || FileUtils.rmdir(path)
    @base.expects(:log!).never
    assert_equal path, @base.log_path
    assert File.directory?(path)
  end

  def test_log_path_path_unable_to_create
    path = File.expand_path('tmp/log_path_test')
    @base.instance_eval { @log_path = nil }
    @base.expects(:fetch).with('log_file_path', 'log').returns('tmp/log_path_test')
    assert !File.directory?(path) || FileUtils.rmdir(path)
    @base.expects(:log!).with("Error creating log directory for New Relic log file: '#{path}'", :error)
    Dir.expects(:mkdir).with(path).raises('cannot make directory bro!')
    assert_equal 'tmp/log_path_test', @base.log_path
    assert !File.directory?(path)
  end

  def test_log_file_name
    @base.expects(:fetch).with('log_file_name', 'newrelic_agent.log').returns('log_file_name')
    assert_equal 'log_file_name', @base.log_file_name
  end
end

