# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/instrumentation/active_record_helper'

module NewRelic::Agent::Instrumentation
  class ActiveRecordHelperTest < Minitest::Test

    def test_product_operation_collection_for_find
      product, operation, collection = ActiveRecordHelper.product_operation_collection_for('Namespace::Model Load', nil, nil)
      assert_equal "ActiveRecord", product
      assert_equal "find", operation
      assert_equal "Namespace::Model", collection
    end

    def test_product_operation_collection_for_destroy
      product, operation, collection = ActiveRecordHelper.product_operation_collection_for('Model Destroy', nil, nil)
      assert_equal "ActiveRecord", product
      assert_equal "destroy", operation
      assert_equal "Model", collection
    end

    def test_product_operation_collection_for_create
      product, operation, collection = ActiveRecordHelper.product_operation_collection_for('Model Create', nil, nil)
      assert_equal "ActiveRecord", product
      assert_equal "create", operation
      assert_equal "Model", collection
    end

    def test_product_operation_collection_for_update
      product, operation, collection = ActiveRecordHelper.product_operation_collection_for('Model Update', nil, nil)
      assert_equal "ActiveRecord", product
      assert_equal "update", operation
      assert_equal "Model", collection
    end

    def test_product_operation_collection_for_name_columns
      product, operation, collection = ActiveRecordHelper.product_operation_collection_for('Model Columns', nil, nil)
      assert_equal "ActiveRecord", product
      assert_equal "columns", operation
      assert_equal "Model", collection
    end

    def test_product_operation_collection_for_with_product_name_from_adapter
      product, operation, collection = ActiveRecordHelper.product_operation_collection_for('Model Load', nil, "mysql")
      assert_equal "MySQL", product
      assert_equal "find", operation
      assert_equal "Model", collection
    end

    def test_product_operation_collection_for_from_sql
      product, operation, collection = ActiveRecordHelper.product_operation_collection_for('invalid', "SELECT * FROM boo", nil)
      assert_equal "ActiveRecord", product
      assert_equal "select", operation
      assert_nil collection
    end

    def test_product_operation_collection_for_name_with_integer_returns_nil
      product, operation, collection = ActiveRecordHelper.product_operation_collection_for(1, '', nil)
      assert_equal "ActiveRecord", product
      assert_equal "other", operation
      assert_nil collection
    end

    def test_rollup_metrics_for_is_deprecated
      NewRelic::Agent::Deprecator.expects(:deprecate)
      result = ActiveRecordHelper.rollup_metrics_for("boo")
      assert_equal ["Datastore/allOther", "Datastore/all"], result
    end

    SUPPORTED_PRODUCTS = ["Postgres", "MySQL"]

    load_cross_agent_test('datastores/datastore_instances').each do |test|
      next unless SUPPORTED_PRODUCTS.include?(test['product'])

      define_method :"test_#{test['name'].tr(' ', '_')}" do
        NewRelic::Agent.drop_buffered_data
        NewRelic::Agent::Hostname.stubs(:get).returns(test['system_hostname'])

        config = convert_test_case_to_config test
        segment = NewRelic::Agent::Transaction.start_datastore_segment config[:adapter], "find", "Blog", ActiveRecordHelper::InstanceIdentifier.for(config)
        segment.finish

        assert_metrics_recorded test['expected_instance_metric']
      end
    end

    CONFIG_NAMES = {
      "db_hostname" => :host,
      "unix_socket" => :socket,
      "port" => :port,
      "product" => :adapter
    }

    def convert_test_case_to_config test_case
      test_case.inject({}) do |memo, (k,v)|
        if config_key = CONFIG_NAMES[k]
          memo[config_key] = v
        end
        memo
      end
    end
  end
end
