# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/instrumentation/active_record_helper'

module NewRelic::Agent::Instrumentation
  class ActiveRecordHelperTest < Minitest::Test

    def test_metrics_for_find
      metrics = ActiveRecordHelper.metrics_for('Namespace::Model Load', nil)
      expected = expected_statement_metrics("find", "Namespace::Model/find")
      assert_equal(expected, metrics)
    end

    def test_metrics_for_destroy
      metrics = ActiveRecordHelper.metrics_for('Model Destroy', nil)
      expected = expected_statement_metrics("destroy", "Model/destroy")
      assert_equal(expected, metrics)
    end

    def test_metrics_for_create
      metrics = ActiveRecordHelper.metrics_for('Model Create', nil)
      expected = expected_statement_metrics("create", "Model/create")
      assert_equal(expected, metrics)
    end

    def test_metrics_for_save
      metrics = ActiveRecordHelper.metrics_for('Model Update', nil)
      expected = expected_statement_metrics("save", "Model/save")
      assert_equal(expected, metrics)
    end

    def test_metric_for_name_columns
      metrics = ActiveRecordHelper.metrics_for('Model Columns', nil)
      expected = expected_statement_metrics("columns", "Model/columns")
      assert_equal(expected, metrics)
    end

    def test_metrics_from_sql
      metrics = ActiveRecordHelper.metrics_for('invalid', "SELECT * FROM boo")
      expected = expected_operation_metrics("select")
      assert_equal(expected, metrics)
    end

    def test_metric_for_name_with_integer_returns_nil
      metrics = ActiveRecordHelper.metrics_for(1, '')
      expected = expected_operation_metrics("other")
      assert_equal(expected, metrics)
    end

    def expected_statement_metrics(operation, statement)
      ["Datastore/statement/ActiveRecord/#{statement}"] +
      expected_operation_metrics(operation)
    end

    def expected_operation_metrics(operation)
      ["Datastore/operation/ActiveRecord/#{operation}",
        "Datastore/ActiveRecord/allOther",
          "Datastore/ActiveRecord/all",
          "Datastore/allOther",
          "Datastore/all"]
    end
  end
end
