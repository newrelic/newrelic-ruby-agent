# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# RUBY-981 Audit Log

require 'newrelic_rpm'

class AuditLogTest < Minitest::Test
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
      $collector.agent_data.each do |req|
        assert_audit_log_contains_object(audit_log_contents, req.body)
      end
    end
  end

  def perform_actions
    state = NewRelic::Agent::TransactionState.tl_get
    NewRelic::Agent.instance.sql_sampler.on_start_transaction(state, nil)
    NewRelic::Agent.instance.sql_sampler.notice_sql("select * from test",
                                 "Database/test/select",
                                 nil, 1.5, state)
    NewRelic::Agent.instance.sql_sampler.on_finishing_transaction(state, 'txn')
    NewRelic::Agent.instance.send(:harvest_and_send_slowest_sql)
  end
end
