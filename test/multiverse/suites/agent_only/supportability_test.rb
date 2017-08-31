1# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'newrelic_rpm'

class SupportabilityTest < Minitest::Test
  include MultiverseHelpers

  def setup
    NewRelic::Agent.manual_start
    NewRelic::Agent.agent.stats_engine.reset!
  end

  def teardown
    NewRelic::Agent.shutdown
  end

  def assert_api_supportability_metric_recorded(method_name)
    assert_metrics_recorded(["Supportability/API/#{method_name}"])
  end

  def test_increment_metric_records_supportability_metric
    NewRelic::Agent.increment_metric('Supportability/PrependedModules/ActiveRecord::Base')
    assert_api_supportability_metric_recorded(:increment_metric)
  end

  def test_record_metric_records_supportability_metric
    NewRelic::Agent.record_metric('foo', 'bar')
    assert_api_supportability_metric_recorded(:record_metric)
  end

  def test_ignore_error_filter_records_supportability_metric
    NewRelic::Agent.ignore_error_filter
    assert_api_supportability_metric_recorded(:ignore_error_filter)
  end

  def test_notice_error_records_supportability_metric
    NewRelic::Agent.notice_error(StandardError)
    assert_api_supportability_metric_recorded(:notice_error)
  end

  def test_record_custom_event_records_supportability_metric
    NewRelic::Agent.record_custom_event(:DummyType, foo: :bar, baz: :qux)
    assert_api_supportability_metric_recorded(:record_custom_event)
  end

  def test_add_instrumentation_records_supportability_metric
    NewRelic::Agent.add_instrumentation 'foo.rb'
    assert_api_supportability_metric_recorded(:add_instrumentation)
  end

  def test_after_fork_records_supportability_metric
    NewRelic::Agent.after_fork { puts 'Foo' }
    assert_api_supportability_metric_recorded(:after_fork)
  end

  def test_drop_buffered_data_records_supportability_metric
    NewRelic::Agent.drop_buffered_data
    assert_api_supportability_metric_recorded(:drop_buffered_data)
  end

  def test_manual_start_records_supportability_metric
    NewRelic::Agent.manual_start
    assert_api_supportability_metric_recorded(:manual_start)
  end

  def test_require_test_helper_records_supportability_metric
    NewRelic::Agent.require_test_helper
    assert_api_supportability_metric_recorded(:require_test_helper)
  end

  def test_set_sql_obfuscator_records_supportability_metric
    NewRelic::Agent.set_sql_obfuscator {}
    assert_api_supportability_metric_recorded(:set_sql_obfuscator)
  end

  def test_shutdown_records_supportability_metric
    NewRelic::Agent.shutdown
    assert_api_supportability_metric_recorded(:shutdown)
  end

  def test_disable_all_tracing_records_supportability_metric
    NewRelic::Agent.disable_all_tracing {}
    assert_api_supportability_metric_recorded(:disable_all_tracing)
  end

  def test_disable_sql_recording_records_supportability_metric
    NewRelic::Agent.disable_sql_recording {}
    assert_api_supportability_metric_recorded(:disable_sql_recording)
  end

  def test_disable_transaction_tracing_records_supportability_metric
    NewRelic::Agent.disable_transaction_tracing {}
    assert_api_supportability_metric_recorded(:disable_transaction_tracing)
  end

  def test_ignore_apdex_records_supportability_metric
    NewRelic::Agent.ignore_apdex
    assert_api_supportability_metric_recorded(:ignore_apdex)
  end

  def test_ignore_enduser_records_supportability_metric
    NewRelic::Agent.ignore_enduser
    assert_api_supportability_metric_recorded(:ignore_enduser)
  end

  def test_ignore_transaction_records_supportability_metric
    NewRelic::Agent.ignore_transaction {}
    assert_api_supportability_metric_recorded(:ignore_transaction)
  end

  def test_add_custom_attributes_records_supportability_metric
    NewRelic::Agent.add_custom_attributes(foo: :bar)
    assert_api_supportability_metric_recorded(:add_custom_attributes)
  end

  def test_get_transaction_name_records_supportability_metric
    NewRelic::Agent.get_transaction_name
    assert_api_supportability_metric_recorded(:get_transaction_name)
  end

  def test_set_transaction_name_records_supportability_metric
    NewRelic::Agent.set_transaction_name('foo')
    assert_api_supportability_metric_recorded(:set_transaction_name)
  end
end