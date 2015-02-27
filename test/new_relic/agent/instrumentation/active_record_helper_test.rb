# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/instrumentation/active_record_helper'

module NewRelic::Agent::Instrumentation
  class ActiveRecordHelperTest < Minitest::Test

    def test_metrics_for_find
      metrics = ActiveRecordHelper.metrics_for('Namespace::Model Load', nil, nil)
      expected = expected_statement_metrics("find", "Namespace::Model/find")
      assert_equal(expected, metrics)
    end

    def test_metrics_for_destroy
      metrics = ActiveRecordHelper.metrics_for('Model Destroy', nil, nil)
      expected = expected_statement_metrics("destroy", "Model/destroy")
      assert_equal(expected, metrics)
    end

    def test_metrics_for_create
      metrics = ActiveRecordHelper.metrics_for('Model Create', nil, nil)
      expected = expected_statement_metrics("create", "Model/create")
      assert_equal(expected, metrics)
    end

    def test_metrics_for_update
      metrics = ActiveRecordHelper.metrics_for('Model Update', nil, nil)
      expected = expected_statement_metrics("update", "Model/update")
      assert_equal(expected, metrics)
    end

    def test_metric_for_name_columns
      metrics = ActiveRecordHelper.metrics_for('Model Columns', nil, nil)
      expected = expected_statement_metrics("columns", "Model/columns")
      assert_equal(expected, metrics)
    end

    def test_metric_with_product_name_from_adapter
      metrics = ActiveRecordHelper.metrics_for('Model Load', nil, "mysql")
      expected = expected_statement_metrics("find", "Model/find", "MySQL")
      assert_equal(expected, metrics)
    end

    def test_metrics_from_sql
      metrics = ActiveRecordHelper.metrics_for('invalid', "SELECT * FROM boo", nil)
      expected = expected_operation_metrics("select")
      assert_equal(expected, metrics)
    end

    def test_metric_for_name_with_integer_returns_nil
      metrics = ActiveRecordHelper.metrics_for(1, '', nil)
      expected = expected_operation_metrics("other")
      assert_equal(expected, metrics)
    end

    def test_rollup_metrics_for_is_deprecated
      NewRelic::Agent::Deprecator.expects(:deprecate)
      result = ActiveRecordHelper.rollup_metrics_for("boo")
      assert_equal ["Datastore/allOther", "Datastore/all"], result
    end

    def expected_statement_metrics(operation, statement, product = "ActiveRecord")
      ["Datastore/statement/#{product}/#{statement}"] +
        expected_operation_metrics(operation, product)
    end

    def expected_operation_metrics(operation, product = "ActiveRecord")
      ["Datastore/operation/#{product}/#{operation}",
        "Datastore/#{product}/allOther",
        "Datastore/#{product}/all",
        "Datastore/allOther",
        "Datastore/all"]
    end
  end
end
