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

      def test_metrics_for_obeys_collection_and_operation_overrides
        in_transaction do
          NewRelic::Agent.with_database_metric_name("Model", "new_method") do
            expected = [
              "Datastore/statement/JonanDB/Model/new_method",
              "Datastore/operation/JonanDB/new_method",
              "Datastore/JonanDB/allOther",
              "Datastore/JonanDB/all",
              "Datastore/allOther",
              "Datastore/all"
            ]

            result = Datastores::MetricHelper.metrics_for(@product, "original_method")
            assert_equal expected, result
          end
        end
      end

      def test_metrics_for_obeys_collection_override
        in_transaction do
          NewRelic::Agent.with_database_metric_name("Model", nil) do
            expected = [
              "Datastore/statement/JonanDB/Model/original_method",
              "Datastore/operation/JonanDB/original_method",
              "Datastore/JonanDB/allOther",
              "Datastore/JonanDB/all",
              "Datastore/allOther",
              "Datastore/all"
            ]

            result = Datastores::MetricHelper.metrics_for(@product, "original_method")
            assert_equal expected, result
          end
        end
      end

      def test_metrics_ignore_overrides_for_other_products
        in_transaction do
          NewRelic::Agent.with_database_metric_name("Model", "new_method", "FauxDB") do
            expected = [
              "Datastore/operation/JonanDB/original_method",
              "Datastore/JonanDB/allOther",
              "Datastore/JonanDB/all",
              "Datastore/allOther",
              "Datastore/all"
            ]

            result = Datastores::MetricHelper.metrics_for(@product, "original_method")
            assert_equal expected, result
          end
        end
      end

      def test_metrics_applies_overrides_by_generic_product_name
        in_transaction do
          NewRelic::Agent.with_database_metric_name("Model", "new_method") do
            expected = [
              "Datastore/statement/MoreSpecificDB/Model/new_method",
              "Datastore/operation/MoreSpecificDB/new_method",
              "Datastore/MoreSpecificDB/allOther",
              "Datastore/MoreSpecificDB/all",
              "Datastore/allOther",
              "Datastore/all"
            ]

            result = Datastores::MetricHelper.metrics_for("MoreSpecificDB", "original_method", nil, @product)
            assert_equal expected, result
          end
        end
      end

    end
  end
end
