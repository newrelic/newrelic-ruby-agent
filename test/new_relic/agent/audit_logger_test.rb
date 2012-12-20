require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/audit_logger'

class AuditLoggerTest < Test::Unit::TestCase
  def setup
    @config = {
      :'audit_log.enabled' => true
    }
    @uri = "http://really.notreal"
    @marshaller = NewRelic::Agent::NewRelicService::Marshaller.new
    @hostname = 'dummyhost'
    Socket.stubs(:gethostname).returns(@hostname)
  end

  def setup_fake_logger
    @fakelog = StringIO.new
    @logger = NewRelic::Agent::AuditLogger.new(@config)
    @logger.stubs(:ensure_log_path).returns(@fakelog)
  end

  def test_never_setup_if_disabled
    config = { :'audit_log.enabled' => false }
    logger = NewRelic::Agent::AuditLogger.new(config)
    logger.expects(:setup_logger).never
    logger.log_request(@uri, "hi there", @marshaller)
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
    logger = NewRelic::Agent::AuditLogger.new(@config.merge(opts))
    assert_nil(logger.ensure_log_path)
  end

  def test_prepares_data_with_identity_encoder
    setup_fake_logger
    data = { 'foo' => 'bar' }
    identity_encoder = NewRelic::Agent::NewRelicService::Encoders::Identity
    @marshaller.expects(:prepare).with(data, { :encoder => identity_encoder })
    @logger.log_request(@uri, data, @marshaller)
  end

  def test_logs_human_readable_data
    setup_fake_logger
    data = {
      'foo' => [1, 2, 3],
      'bar' => {
        'baz' => 'qux',
        'jingle' => 'bells'
      }
    }
    @logger.log_request(@uri, data, @marshaller)
    @fakelog.rewind
    assert(@fakelog.read.include?(data.inspect), "Expected human-readable version of data in log file")
  end
end
