# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# RUBY-981 Audit Log

require 'newrelic_rpm'
require 'multiverse_helpers'

class AuditLogTest < MiniTest::Unit::TestCase
  include MultiverseHelpers

  def setup
    @string_log = StringIO.new
    NewRelic::Agent::AuditLogger.any_instance.stubs(:ensure_log_path).returns(@string_log)
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
    needle = needle.gsub(regex, '')
    haystack = audit_log_contents.gsub(regex, '')
    assert(haystack.include?(needle), "Expected log to contain '#{needle}'")
  end

  # Because we don't generate a strictly machine-readable representation of
  # request bodies for the audit log, the transformation into strings is
  # effectively one-way. This, combined with the fact that Hash traversal order
  # is arbitrary in Ruby 1.8.x means that it's difficult to directly assert that
  # some object graph made it into the audit log (due to different possible
  # orderings of the key/value pairs in Hashes that were embedded in the request
  # body). So, this method traverses an object graph and only makes assertions
  # about the terminal (non-Array-or-Hash) nodes therein.
  def assert_audit_log_contains_object(o, format)
    if format == :json
      assert_audit_log_contains(JSON.dump(o))
    else
      case o
      when Hash
        o.each do |k,v|
          assert_audit_log_contains_object(v, format)
        end
      when Array
        o.each do |el|
          assert_audit_log_contains_object(el, format)
        end
      else
        assert_audit_log_contains(o.inspect)
      end
    end
  end

  def test_logs_nothing_by_default
    run_agent do
      perform_actions
      assert_equal('', audit_log_contents)
    end
  end

  def test_logs_nothing_when_disabled
    run_agent(:'audit_log.enabled' => false) do
      perform_actions
      assert_equal('', audit_log_contents)
    end
  end

  def test_logs_request_bodies_human_readably_ish
    run_agent(:'audit_log.enabled' => true) do
      perform_actions
      format = NewRelic::Agent::NewRelicService::JsonMarshaller.is_supported? ? :json : :pruby
      $collector.agent_data.each do |req|
        assert_audit_log_contains_object(req.body, format)
      end
    end
  end

  def perform_actions
    reset_collector

    NewRelic::Agent.instance.sql_sampler.notice_first_scope_push(nil)
    NewRelic::Agent.instance.sql_sampler.notice_sql("select * from test",
                                 "Database/test/select",
                                 nil, 1.5)
    NewRelic::Agent.instance.sql_sampler.notice_scope_empty('txn')
    NewRelic::Agent.instance.send(:harvest_and_send_slowest_sql)
  end
end
