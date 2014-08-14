# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/instrumentation/active_record_helper'

class NewRelic::Agent::Instrumentation::ActiveRecordHelperTest < Minitest::Test
  include NewRelic::Agent::Instrumentation

  def test_metric_for_name_find
    metric_name = 'ActiveRecord/Model/find'
    assert_equal metric_name, ActiveRecordHelper.metric_for_name('Model Find')
    assert_equal metric_name, ActiveRecordHelper.metric_for_name('Model Load')
    assert_equal metric_name, ActiveRecordHelper.metric_for_name('Model Count')
    assert_equal metric_name, ActiveRecordHelper.metric_for_name('Model Exists')
  end

  def test_metric_for_name_with_namespace
    assert_equal('ActiveRecord/Namespace::Model/find',
                 ActiveRecordHelper.metric_for_name('Namespace::Model Load'))
  end

  def test_metric_for_name_destroy
    assert_equal('ActiveRecord/Model/destroy',
                 ActiveRecordHelper.metric_for_name('Model Destroy'))
  end

  def test_metric_for_name_create
    assert_equal('ActiveRecord/Model/create',
                 ActiveRecordHelper.metric_for_name('Model Create'))
  end

  def test_metric_for_name_update
    assert_equal('ActiveRecord/Model/save',
                 ActiveRecordHelper.metric_for_name('Model Update'))
  end

  def test_metric_for_name_columns
    assert_nil ActiveRecordHelper.metric_for_name('Model Columns')
  end

  def test_metric_for_name_with_integer_returns_nil
    assert_nil ActiveRecordHelper.metric_for_name(1)
  end

  def test_rollup_metrics_for_lists_rollups
    NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(true)
    base_metric = 'ActiveRecord/Namespace::Model/find'
    rollup_metrics = ActiveRecordHelper.rollup_metrics_for(base_metric)
    expected_metrics = ['Datastore/all', 'ActiveRecord/all', 'ActiveRecord/find']
    assert_equal(expected_metrics.sort, rollup_metrics.sort)
  end

  def test_rollup_metrics_for_skips_operation_rollup_given_metric_without_model
    NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(true)
    rollup_metrics = ActiveRecordHelper.rollup_metrics_for('ActiveRecord/find')
    expected_metrics = ['Datastore/all', 'ActiveRecord/all']
    assert_equal(expected_metrics, rollup_metrics)
  end

  def test_rollup_metrics_for_omits_database_all_outside_web_transaction
    NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(false)
    base_metric = 'ActiveRecord/Namespace::Model/find'
    rollup_metrics = ActiveRecordHelper.rollup_metrics_for(base_metric)
    assert_equal(['Datastore/all', 'Datastore/allOther', 'ActiveRecord/find'], rollup_metrics)
  end

  def test_remote_service_metric
    assert_equal('RemoteService/sql/mysql/server',
                 ActiveRecordHelper.remote_service_metric('mysql', 'server'))
  end
end
