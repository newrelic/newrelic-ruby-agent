# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/datastores/metric_helper'

module NewRelic
  module Agent
    class Datastores::MetricHelperTest < Minitest::Test
      def setup
        @product = "JonanDB"
        @collection = "wiggles"
        @operation = "select"
      end

      def test_statement_metric_for
        expected = "Datastore/statement/JonanDB/wiggles/select"
        result = Datastores::MetricHelper.statement_metric_for(@product, @collection, @operation)
        assert_equal expected, result
      end

      def test_operation_metric_for
        expected = "Datastore/operation/JonanDB/select"
        result = Datastores::MetricHelper.operation_metric_for(@product, @operation)
        assert_equal expected, result
      end

      def test_metrics_for_in_web_context
        Transaction.stubs(:recording_web_transaction?).returns(true)
        expected = [
          "Datastore/statement/JonanDB/wiggles/select",
          "Datastore/operation/JonanDB/select",
          "Datastore/JonanDB/allWeb",
          "Datastore/JonanDB/all",
          "Datastore/allWeb",
          "Datastore/all"
        ]

        result = Datastores::MetricHelper.metrics_for(@product, @operation, @collection)
        assert_equal expected, result
      end

      def test_metrics_for_outside_web_context
        Transaction.stubs(:recording_web_transaction?).returns(false)
        expected = [
          "Datastore/statement/JonanDB/wiggles/select",
          "Datastore/operation/JonanDB/select",
          "Datastore/JonanDB/allOther",
          "Datastore/JonanDB/all",
          "Datastore/allOther",
          "Datastore/all"
        ]

        result = Datastores::MetricHelper.metrics_for(@product, @operation, @collection)
        assert_equal expected, result
      end

      def test_scoped_metric_for_with_collection
        expected = "Datastore/statement/JonanDB/wiggles/select"
        result = Datastores::MetricHelper.scoped_metric_for(@product, @operation, @collection)
        assert_equal expected, result
      end

      def test_scoped_metric_for_without_collection
        expected = "Datastore/operation/JonanDB/select"
        result = Datastores::MetricHelper.scoped_metric_for(@product, @operation)
        assert_equal expected, result
      end

      def test_unscoped_metrics_for_in_web_context
        Transaction.stubs(:recording_web_transaction?).returns(true)
        expected = [
          "Datastore/operation/JonanDB/select",
          "Datastore/JonanDB/allWeb",
          "Datastore/JonanDB/all",
          "Datastore/allWeb",
          "Datastore/all"
        ]

        result = Datastores::MetricHelper.unscoped_metrics_for(@product, @operation, @collection)
        assert_equal expected, result
      end

      def test_unscoped_metrics_for_outside_web_context
        Transaction.stubs(:recording_web_transaction?).returns(false)
        expected = [
          "Datastore/operation/JonanDB/select",
          "Datastore/JonanDB/allOther",
          "Datastore/JonanDB/all",
          "Datastore/allOther",
          "Datastore/all"
        ]

        result = Datastores::MetricHelper.unscoped_metrics_for(@product, @operation, @collection)
        assert_equal expected, result
      end

      def test_unscoped_metrics_for_without_collection
        Transaction.stubs(:recording_web_transaction?).returns(false)
        expected = [
          "Datastore/JonanDB/allOther",
          "Datastore/JonanDB/all",
          "Datastore/allOther",
          "Datastore/all"
        ]

        result = Datastores::MetricHelper.unscoped_metrics_for(@product, @operation)
        assert_equal expected, result
      end

      def test_product_operation_collection_for_obeys_collection_and_operation_overrides
        in_transaction do
          NewRelic::Agent.with_database_metric_name("Model", "new_method") do
            result = Datastores::MetricHelper.product_operation_collection_for(@product, "original_method")
            expected = [@product, "new_method", "Model"]
            assert_equal expected, result
          end
        end
      end

      def test_product_operation_collection_for_obeys_collection_override
        in_transaction do
          NewRelic::Agent.with_database_metric_name("Model", nil) do
            result = Datastores::MetricHelper.product_operation_collection_for(@product, "original_method")
            expected = [@product, "original_method", "Model"]
            assert_equal expected, result
          end
        end
      end

      def test_product_operation_collection_for_ignore_overrides_for_other_products
        in_transaction do
          NewRelic::Agent.with_database_metric_name("Model", "new_method", "FauxDB") do
            result = Datastores::MetricHelper.product_operation_collection_for(@product, "original_method")
            expected = [@product, "original_method", nil]
            assert_equal expected, result
          end
        end
      end

      def test_product_operation_collection_for_applies_overrides_by_generic_product_name
        in_transaction do
          NewRelic::Agent.with_database_metric_name("Model", "new_method") do
            result = Datastores::MetricHelper.product_operation_collection_for("MoreSpecificDB", "original_method", nil, @product)
            expected = ["MoreSpecificDB", "new_method", "Model"]
            assert_equal expected, result
          end
        end
      end

      def test_operation_from_sql
        sql = "SELECT * FROM blogs where id = 5"
        operation = Datastores::MetricHelper.operation_from_sql sql
        assert_equal "select", operation
      end

      def test_operation_from_sql_returns_other_for_unrecognized_operation
        sql = "DESCRIBE blogs"
        operation = Datastores::MetricHelper.operation_from_sql sql
        assert_equal "Other", operation
      end
    end
  end
end
