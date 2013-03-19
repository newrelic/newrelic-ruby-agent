# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/audit_logger'
require 'new_relic/agent/null_logger'

class AuditLoggerTest < Test::Unit::TestCase
  def setup
    @config = {
      :'audit_log.enabled' => true
    }
    @uri = "http://really.notreal"
    @marshaller = NewRelic::Agent::NewRelicService::Marshaller.new
    @hostname = 'dummyhost'
    @dummy_data = {
      'foo' => [1, 2, 3],
      'bar' => {
        'baz' => 'qux',
        'jingle' => 'bells'
      }
    }
    Socket.stubs(:gethostname).returns(@hostname)
  end

  def setup_fake_logger
    @fakelog = StringIO.new
    @logger = NewRelic::Agent::AuditLogger.new(@config)
    @logger.stubs(:ensure_log_path).returns(@fakelog)
  end

  def assert_log_contains_string(str)
    @fakelog.rewind
    log_body = @fakelog.read
    assert(log_body.include?(str), "Expected log to contain string '#{str}'")
  end

  def test_never_setup_if_disabled
    config = { :'audit_log.enabled' => false }
    logger = NewRelic::Agent::AuditLogger.new(config)
    logger.log_request(@uri, "hi there", @marshaller)
    assert(!logger.setup?, "Expected logger to not have been setup")
  end

  def test_never_prepare_if_disabled
    config = { :'audit_log.enabled' => false }
    logger = NewRelic::Agent::AuditLogger.new(config)
    marshaller = NewRelic::Agent::NewRelicService::Marshaller.new
    marshaller.expects(:prepare).never
    logger.log_request(@uri, "hi there", @marshaller)
  end

  def test_log_formatter
    formatter = NewRelic::Agent::AuditLogger.new(@config).log_formatter
    time = '2012-01-01 00:00:00'
    msg = 'hello'
    result = formatter.call(Logger::INFO, time, 'bleh', msg)
    expected = "[2012-01-01 00:00:00 #{@hostname} (#{$$})] : hello\n"
    assert_equal(expected, result)
  end

  def test_ensure_path_returns_nil_with_bogus_path
    opts = { :'audit_log.path' => '/really/really/not/a/path' }
    FileUtils.stubs(:mkdir_p).raises(SystemCallError, "i'd rather not")
    logger = NewRelic::Agent::AuditLogger.new(@config.merge(opts))
    assert_nil(logger.ensure_log_path)
  end

  def test_setup_logger_creates_null_logger_when_ensure_path_fails
    null_logger = NewRelic::Agent::NullLogger.new
    NewRelic::Agent::NullLogger.expects(:new).returns(null_logger)
    logger = NewRelic::Agent::AuditLogger.new(@config)
    logger.stubs(:ensure_log_path).returns(nil)
    assert_nothing_raised do
      logger.setup_logger
      logger.log_request(@uri, 'whatever', @marshaller)
    end
  end

  def test_log_request_captures_system_call_errors
    logger = NewRelic::Agent::AuditLogger.new(@config)
    dummy_sink = StringIO.new
    dummy_sink.stubs(:write).raises(SystemCallError, "nope")
    logger.stubs(:ensure_log_path).returns(dummy_sink)

    # In 1.9.2 and later, Logger::LogDevice#write captures any errors during
    # writing and spits them out with Kernel#warn.
    # This just silences that output to keep the test output uncluttered.
    Logger::LogDevice.any_instance.stubs(:warn)

    assert_nothing_raised do
      logger.log_request(@uri, 'whatever', @marshaller)
    end
  end

  def test_prepares_data_with_identity_encoder
    setup_fake_logger
    data = { 'foo' => 'bar' }
    identity_encoder = NewRelic::Agent::NewRelicService::Encoders::Identity
    @marshaller.expects(:prepare).with(data, { :encoder => identity_encoder })
    @logger.log_request(@uri, data, @marshaller)
  end

  def test_logs_inspect_with_pruby_marshaller
    setup_fake_logger
    pruby_marshaller = NewRelic::Agent::NewRelicService::PrubyMarshaller.new
    @logger.log_request(@uri, @dummy_data, pruby_marshaller)
    assert_log_contains_string(@dummy_data.inspect)
  end

  def test_logs_json_with_json_marshaller
    marshaller_cls = NewRelic::Agent::NewRelicService::JsonMarshaller
    if marshaller_cls.is_supported?
      setup_fake_logger
      json_marshaller = marshaller_cls.new
      @logger.log_request(@uri, @dummy_data, json_marshaller)
      assert_log_contains_string(JSON.dump(@dummy_data))
    end
  end
end
