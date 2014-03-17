# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.join(File.dirname(__FILE__), '..', '..', '..', 'agent_helper')
require 'multiverse_helpers'

class TransactionIgnoringTest < Minitest::Test

  include MultiverseHelpers

  TXN_PREFIX = 'Controller/TransactionIgnoringTest::TestWidget/'

  setup_and_teardown_agent do |collector|
    collector.stub('connect', {
      'transaction_name_rules' => [{"match_expression" => "ignored_transaction",
                                    "ignore"           => true}],
      'agent_run_id' => 1,
    })
  end

  class TestWidget
    include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation

    def ignored_transaction
      yield if block_given?
    end
    add_transaction_tracer :ignored_transaction

    def accepted_transaction
      yield if block_given?
    end
    add_transaction_tracer :accepted_transaction
  end

  def test_does_not_record_metrics_for_ignored_transaction
    TestWidget.new.ignored_transaction
    TestWidget.new.accepted_transaction

    NewRelic::Agent.instance.send(:harvest_and_send_timeslice_data)

    stats = $collector.reported_stats_for_metric(TXN_PREFIX+'accepted_transaction')
    assert_equal(1, stats.size)

    stats = $collector.reported_stats_for_metric(TXN_PREFIX+'ignored_transaction')
    assert_equal(0, stats.size)
  end

  def test_does_not_record_traced_errors_for_ignored_transactions
    TestWidget.new.ignored_transaction  { NewRelic::Agent.notice_error('Buffy dies :(' ) }
    TestWidget.new.accepted_transaction { NewRelic::Agent.notice_error('Buffy lives :)') }

    NewRelic::Agent.instance.send(:harvest_and_send_errors)

    posts = $collector.calls_for('error_data')
    assert_equal(1, posts.size)

    errors = posts.first.errors

    assert_equal(1, errors.size)
    assert_equal('Buffy lives :)', errors.first.message)
  end

  def test_does_not_record_transaction_trace_for_ignored_transactions
    with_config(:'transaction_tracer.transaction_threshold' => 0) do
      TestWidget.new.accepted_transaction
      NewRelic::Agent.instance.send(:harvest_and_send_transaction_traces)
      assert_equal(1, $collector.calls_for('transaction_sample_data').size)

      TestWidget.new.ignored_transaction
      NewRelic::Agent.instance.send(:harvest_and_send_transaction_traces)
      assert_equal(1, $collector.calls_for('transaction_sample_data').size)
    end
  end

  def test_does_not_record_analytics_for_ignored_transactions
    TestWidget.new.ignored_transaction
    TestWidget.new.accepted_transaction

    NewRelic::Agent.instance.send(:harvest_and_send_analytic_event_data)

    posts = $collector.calls_for('analytic_event_data')
    assert_equal(1, posts.size)

    events = posts.first.events

    assert_equal(1, events.size)
    assert_equal(TXN_PREFIX+'accepted_transaction', events.first[0]['name'])
  end

end
