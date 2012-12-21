# RUBY-981 Audit Log

require 'newrelic_rpm'
require 'fake_collector'
require 'mocha'

class AuditLogTest < Test::Unit::TestCase
  # Initialization
  def setup
    $collector ||= NewRelic::FakeCollector.new
    $collector.reset
    $collector.run

    NewRelic::Agent.reset_config 
    @string_log = StringIO.new
    NewRelic::Agent::AuditLogger.any_instance.stubs(:ensure_log_path).returns(@string_log)
  end

  def teardown
    $collector.reset
  end

  def audit_log_contents
    if @contents.nil?
      @string_log.rewind
      @contents = @string_log.read
    end
    @contents
  end

  def assert_audit_log_contains(needle)
    # Original request bodies dumped to the log have symbol keys, but once
    # they go through a dump/load, they're strings again, so we strip
    # double-quotes and colons from the log, and the strings we searching for.
    regex = /[:"]/
    needle = needle.inspect.gsub(regex, '')
    haystack = audit_log_contents.gsub(regex, '')
    assert(haystack.include?(needle), "Expected log to contain '#{needle}'")
  end

  def run_agent_with_options(options)
    NewRelic::Agent.manual_start(options)
    yield NewRelic::Agent.agent if block_given?
    NewRelic::Agent.shutdown    
  end

  def test_logs_nothing_by_default
    run_agent_with_options({})
    assert_equal('', audit_log_contents)
  end

  def test_logs_nothing_when_disabled
    run_agent_with_options({ :'audit_log.enabled' => false })
    assert_equal('', audit_log_contents)
  end

  def test_logs_request_bodies_human_readably_ish
    run_agent_with_options({ :'audit_log.enabled' => true }) do |agent|
      agent.sql_sampler.notice_first_scope_push(nil)
      agent.sql_sampler.notice_sql("select * from test",
                                    "Database/test/select",
                                    nil, 1.5)
      agent.sql_sampler.notice_scope_empty
      agent.send(:harvest_and_send_slowest_sql)
    end

    $collector.agent_data.each do |req|
      body = $collector.unpack_inner_blobs(req)
      assert_audit_log_contains(body)
    end
  end
end
