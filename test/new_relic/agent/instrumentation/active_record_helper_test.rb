# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/instrumentation/active_record_helper'

module Animals
  class Dog
    def self.table_name
      'animals'
    end
  end
end

module NewRelic::Agent::Instrumentation
  class ActiveRecordHelperTest < Minitest::Test
    def teardown
      ActiveRecordHelper::TABLE_NAME_CACHE.clear
    end

    def test_product_operation_collection_for_find
      product, operation, collection = ActiveRecordHelper.product_operation_collection_for('Namespace::Model Load', nil, nil)

      assert_equal 'ActiveRecord', product
      assert_equal 'find', operation
      assert_equal 'Namespace::Model', collection
    end

    def test_product_operation_collection_for_destroy
      product, operation, collection = ActiveRecordHelper.product_operation_collection_for('Model Destroy', nil, nil)

      assert_equal 'ActiveRecord', product
      assert_equal 'destroy', operation
      assert_equal 'Model', collection
    end

    def test_product_operation_collection_for_create
      product, operation, collection = ActiveRecordHelper.product_operation_collection_for('Model Create', nil, nil)

      assert_equal 'ActiveRecord', product
      assert_equal 'create', operation
      assert_equal 'Model', collection
    end

    def test_product_operation_collection_for_update
      product, operation, collection = ActiveRecordHelper.product_operation_collection_for('Model Update', nil, nil)

      assert_equal 'ActiveRecord', product
      assert_equal 'update', operation
      assert_equal 'Model', collection
    end

    def test_product_operation_collection_for_name_columns
      product, operation, collection = ActiveRecordHelper.product_operation_collection_for('Model Columns', nil, nil)

      assert_equal 'ActiveRecord', product
      assert_equal 'columns', operation
      assert_equal 'Model', collection
    end

    def test_product_operation_collection_for_with_product_name_from_adapter
      product, operation, collection = ActiveRecordHelper.product_operation_collection_for('Model Load', nil, 'mysql')

      assert_equal 'MySQL', product
      assert_equal 'find', operation
      assert_equal 'Model', collection
    end

    def test_product_operation_collection_for_with_product_name_from_adapter_trilogy
      product, _operation, _collection = ActiveRecordHelper.product_operation_collection_for(nil, '', 'trilogy')

      assert_equal 'MySQL', product
    end

    def test_product_operation_collection_for_from_sql
      product, operation, collection = ActiveRecordHelper.product_operation_collection_for('invalid', 'SELECT * FROM boo', nil)

      assert_equal 'ActiveRecord', product
      assert_equal 'select', operation
      assert_nil collection
    end

    def test_product_operation_collection_for_timestream_from_adapter
      product, operation, collection = ActiveRecordHelper.product_operation_collection_for('Model Load',
        nil,
        'amazon_timestream')

      assert_equal 'Timestream', product
      assert_equal 'find', operation
      assert_equal 'Model', collection
    end

    def test_product_operation_collection_for_name_with_integer_returns_nil
      product, operation, collection = ActiveRecordHelper.product_operation_collection_for(1, '', nil)

      assert_equal 'ActiveRecord', product
      assert_equal 'other', operation
      assert_nil collection
    end

    def test_suffixes_are_stripped_away_from_the_adapter_name
      assert_equal 'postgresql', ActiveRecordHelper.bare_adapter_name('postgresql_makara')
    end

    def test_product_operation_collection_for_handles_suffixes
      product, _operation, _collection = ActiveRecordHelper.product_operation_collection_for(1, '', 'postgresql_makara')

      assert_equal 'Postgres', product
    end

    def test_suffixes_on_configuration_based_adapter_names_are_stripped_away
      config = {adapter: 'postgresql_makara'}
      adapter = NewRelic::Agent::Instrumentation::ActiveRecordHelper::InstanceIdentification.adapter_from_config(config)

      assert_equal :postgres, adapter
    end

    def test_table_name_result_is_stored_in_cache
      with_config(active_record_use_table_name: true) do
        ActiveRecordHelper.product_operation_collection_for('Animals::Dog Load', nil, nil)
      end

      assert ActiveRecordHelper::TABLE_NAME_CACHE.key?('Animals::Dog')
    end

    def test_cached_table_name_is_returned_without_resolving_again
      ActiveRecordHelper::TABLE_NAME_CACHE['Animals::Dog'] = 'animals'

      ActiveRecordHelper.stub(:resolve_table_name, ->(_) { raise 'should not be called' }) do
        with_config(active_record_use_table_name: true) do
          _product, _operation, collection = ActiveRecordHelper.product_operation_collection_for('Animals::Dog Load', nil, nil)

          assert_equal 'animals', collection
        end
      end
    end

    def test_class_name_used_for_namespaced_model_by_default
      with_config(active_record_use_table_name: false) do
        _product, _operation, collection = ActiveRecordHelper.product_operation_collection_for('Animals::Dog Load', nil, nil)

        assert_equal 'Animals::Dog', collection
      end
    end

    def test_table_name_used_for_namespaced_model_when_configured
      with_config(active_record_use_table_name: true) do
        _product, _operation, collection = ActiveRecordHelper.product_operation_collection_for('Animals::Dog Load', nil, nil)

        assert_equal 'animals', collection
      end
    end

    def test_class_name_used_as_fallback_when_model_unresolvable
      with_config(active_record_use_table_name: true) do
        _product, _operation, collection = ActiveRecordHelper.product_operation_collection_for('Unresolvable::Model Load', nil, nil)

        assert_equal 'Unresolvable::Model', collection
      end
    end
  end
end
