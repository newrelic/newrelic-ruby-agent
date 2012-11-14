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
    NewRelic::Control.instance.instance_variable_set '@log_path', nil
    NewRelic::Control.instance.instance_variable_set '@log_file', nil
    @root = ::Rails::VERSION::MAJOR == 3 ? Rails.root : RAILS_ROOT
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
    @base.stubs(:to_stdout)
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
    with_config(:agent_enabled => false) do
      assert !@base.should_log?
    end
  end

  def test_should_log_agent_enabled
    @base.instance_eval { @settings = true }
    with_config(:agent_enabled => true) do
      assert @base.should_log?
    end
  end

  def test_set_log_level_base
    fake_logger = mock('logger')
    # bad configuration
    with_config(:log_level => 'whee') do
      fake_logger.expects(:level=).with(Logger::INFO)
      assert_equal fake_logger, @base.set_log_level!(fake_logger)
    end
  end

  def test_set_log_level_with_each_level
    fake_logger = mock('logger')
    %w[debug info warn error fatal].each do |level|
      with_config(:log_level => level) do
        fake_logger.expects(:level=).with(Logger.const_get(level.upcase))
        assert_equal fake_logger, @base.set_log_level!(fake_logger)
      end
    end
  end

  def test_set_log_format
    fake_logger = Object.new
    assert !fake_logger.respond_to?(:format_message)
    assert_equal fake_logger, @base.set_log_format!(fake_logger)
    assert fake_logger.respond_to?(:format_message)
  end

  def test_setup_log_existing_file
    fake_logger = mock('logger')
    Logger.expects(:new).returns(fake_logger)
    @base.expects(:set_log_format!).with(fake_logger)
    @base.expects(:set_log_level!).with(fake_logger)
    with_config(:log_file_path => 'logpath', :log_file_name => 'logfilename') do
      assert_equal fake_logger, @base.setup_log
      assert_equal fake_logger, @base.instance_eval { @log }
      assert_match(/logpath\/logfilename$/, @base.instance_eval { @log_file })
    end
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
    with_config(:log_file_path => 'log') do
      assert File.directory?('log')
      assert_equal File.expand_path('log'), @base.log_path
    end
  end

  def test_log_path_path_created
    path = File.expand_path('tmp/log_path_test')
    FileUtils.mkdir_p(File.dirname(path))
    @base.instance_eval { @log_path = nil }
    with_config(:log_file_path => 'tmp/log_path_test') do
      assert !File.directory?(path) || FileUtils.rmdir(path)
      @base.expects(:log!).never
      assert_equal path, @base.log_path
      assert File.directory?(path)
    end
  end

  def test_log_path_path_unable_to_create
    path = File.expand_path('tmp/log_path_test')
    @base.instance_eval { @log_path = nil }
    with_config(:log_file_path => 'tmp/log_path_test') do
      assert !File.directory?(path) || FileUtils.rmdir(path)
      @base.expects(:log!).with("Error creating log directory tmp/log_path_test, using standard out for logging.", :warn)
      # once for the relative directory, once for the directory relative to Rails.root
      Dir.expects(:mkdir).with(path).raises('cannot make directory bro!').twice
      assert_nil @base.log_path
      assert !File.directory?(path)
      assert_equal STDOUT, @base.log.instance_eval { @logdev }.dev
    end
  end

  def test_log_to_stdout_when_log_file_path_set_to_STDOUT
    Dir.expects(:mkdir).never
    with_config(:log_file_path => 'STDOUT') do
      @base.setup_log
      assert_equal STDOUT, @base.log.instance_eval { @logdev }.dev
    end
  end

  def test_logs_to_stdout_include_newrelic_prefix
    with_config(:log_file_path => 'STDOUT') do
      STDOUT.expects(:write).with(regexp_matches(/\*\* \[NewRelic\].*whee/))
      @base.setup_log
      @base.log.info('whee')
    end
  end

  def test_set_stdout_destination_from_NEW_RELIC_LOG_env_var
    ENV['NEW_RELIC_LOG'] = 'stdout'
    reset_environment_config
    Dir.expects(:mkdir).never
    @base.setup_log
    assert_equal STDOUT, @base.log.instance_eval { @logdev }.dev
    ENV['NEW_RELIC_LOG'] = nil
    reset_environment_config
  end

  def test_set_file_destination_from_NEW_RELIC_LOG_env_var
    ENV['NEW_RELIC_LOG'] = 'log/file.log'
    reset_environment_config
    @base.setup_log
    assert_equal 'log', File.basename(@base.log_path)
    assert_equal 'file.log', NewRelic::Agent.config['log_file_name']
    ENV['NEW_RELIC_LOG'] = nil
    reset_environment_config
  end

  def test_log_path_uses_default_if_not_set
    NewRelic::Control.instance.setup_log
    assert_match(/log\/newrelic_agent.log$/,
                 NewRelic::Control.instance.log_file)
  end

  def test_log_file_path_uses_given_value
    Dir.stubs(:mkdir).returns(true)
    with_config(:log_file_path => 'lerg') do
      NewRelic::Control.instance.setup_log
      assert_match(/\/lerg\/newrelic_agent.log$/,
                   NewRelic::Control.instance.log_file)
    end
  end

  def reset_environment_config
    NewRelic::Agent.config.config_stack[0] =
      NewRelic::Agent::Configuration::EnvironmentSource.new
  end
end
