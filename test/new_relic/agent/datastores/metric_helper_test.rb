# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../../../test_helper'
require 'new_relic/agent/datastores/metric_helper'

module NewRelic
  module Agent
    class Datastores::MetricHelperTest < Minitest::Test
      def setup
        @product = "JonanDB"
        @collection = "wiggles"
        @operation = "select"
        NewRelic::Agent::Harvester.any_instance.stubs(:harvest_thread_enabled?).returns(false)
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

      def test_instance_metric_for
        host = "localhost"
        port = "1337807"
        expected = "Datastore/instance/JonanDB/#{host}/#{port}"
        result = Datastores::MetricHelper.instance_metric_for(@product, host, port)
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

      def test_unscoped_metrics_for_with_instance_identifier
        Transaction.stubs(:recording_web_transaction?).returns(false)
        expected = [
          "Datastore/instance/JonanDB/localhost/1337807",
          "Datastore/JonanDB/allOther",
          "Datastore/JonanDB/all",
          "Datastore/allOther",
          "Datastore/all"
        ]

        result = Datastores::MetricHelper.unscoped_metrics_for(@product, @operation, nil, "localhost", "1337807")
        assert_equal expected, result
      end

      def test_unscoped_metrics_for_with_instance_identifier_and_instance_reporting_disabled
        with_config(:'datastore_tracer.instance_reporting.enabled' => false) do
          Transaction.stubs(:recording_web_transaction?).returns(false)
          expected = [
            "Datastore/JonanDB/allOther",
            "Datastore/JonanDB/all",
            "Datastore/allOther",
            "Datastore/all"
          ]

          result = Datastores::MetricHelper.unscoped_metrics_for(@product, @operation, nil, "localhost/1337807")
          assert_equal expected, result
        end
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
