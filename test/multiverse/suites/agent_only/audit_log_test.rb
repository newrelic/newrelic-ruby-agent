# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

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
      assert_empty($collector.calls_for(:log_event_data))
    end
  end

  def test_logs_nothing_when_disabled
    run_agent(:'audit_log.enabled' => false) do
      perform_actions

      assert_equal('', audit_log_contents)
      assert_empty($collector.calls_for(:log_event_data))
    end
  end

  def test_logs_request_bodies_human_readably_ish
    run_agent(:'audit_log.enabled' => true) do
      perform_actions

      $collector.agent_data.each do |req|
        assert_audit_log_contains_object(audit_log_contents, req.body)
      end

      assert_empty($collector.calls_for(:log_event_data))
    end
  end

  def perform_actions
    state = NewRelic::Agent::Tracer.state
    NewRelic::Agent.instance.sql_sampler.on_start_transaction(state)
    NewRelic::Agent.instance.sql_sampler.notice_sql("select * from test",
      "Database/test/select",
      nil, 1.5, state)
    NewRelic::Agent.instance.sql_sampler.on_finishing_transaction(state, 'txn')
    NewRelic::Agent.instance.send(:harvest_and_send_slowest_sql)

    # We also trigger log event data sending because we shouldn't see any
    NewRelic::Agent.instance.send(:harvest_and_send_log_event_data)
  end
end
