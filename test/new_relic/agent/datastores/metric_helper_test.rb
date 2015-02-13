# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/datastores/metric_helper'
require 'set'

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

      def test_context_metric_returns_web_for_web_context
        NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(true)
        expected = "Datastore/allWeb"
        result = Datastores::MetricHelper.context_metric
        assert_equal expected, result
      end

      def test_context_metric_returns_other_for_non_web_context
        NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(false)
        expected = "Datastore/allOther"
        result = Datastores::MetricHelper.context_metric
        assert_equal expected, result
      end

      def test_metrics_for_in_web_context
        Transaction.stubs(:recording_web_transaction?).returns(true)
        expected = Set.new [
          "Datastore/all",
          "Datastore/allWeb",
          "Datastore/JonanDB/all",
          "Datastore/JonanDB/allWeb",
          "Datastore/statement/JonanDB/wiggles/select",
          "Datastore/operation/JonanDB/select"
        ]

        result = Datastores::MetricHelper.metrics_for(@product, @operation, @collection)
        assert_equal expected, result.to_set
      end

      def test_metrics_for_outside_web_context
        Transaction.stubs(:recording_web_transaction?).returns(false)
        expected = Set.new [
          "Datastore/all",
          "Datastore/allOther",
          "Datastore/JonanDB/all",
          "Datastore/JonanDB/allOther",
          "Datastore/statement/JonanDB/wiggles/select",
          "Datastore/operation/JonanDB/select"
        ]

        result = Datastores::MetricHelper.metrics_for(@product, @operation, @collection)
        assert_equal expected, result.to_set
      end

      def test_active_record_metric_for_name
        names = {
          "Wiggles Load" => "Datastore/Wiggles/find",
          "Wiggles Count" => "Datastore/Wiggles/find",
          "Wiggles Exists" => "Datastore/Wiggles/find",
          "Wiggles Indexes" => nil,
          "Wiggles Columns" => nil,
          "Wiggles Destroy" => "Datastore/Wiggles/destroy",
          "Wiggles Find" => "Datastore/Wiggles/find",
          "Wiggles Save" => "Datastore/Wiggles/save",
          "Wiggles Create" => "Datastore/Wiggles/create",
          "Wiggles Update" => "Datastore/Wiggles/save"
        }

        names.each do |name, expected|
          result = Datastores::MetricHelper.active_record_metric_for_name(name)
          assert_equal expected, result
        end
      end

      def test_active_record_metric_for_name_returns_nil_given_nil
        result = Datastores::MetricHelper.active_record_metric_for_name(nil)
        assert_nil result
      end

      def test_active_record_metric_for_name_returns_nil_given_a_spaceless_string
        result = Datastores::MetricHelper.active_record_metric_for_name('load')
        assert_nil result
      end

      def test_active_record_metric_for_name_returns_nil_given_a_string_with_three_spaces
        result = Datastores::MetricHelper.active_record_metric_for_name('load count exists')
        assert_nil result
      end

      def test_product_is_named_properly_for_mysql_adapter
        product_name = Datastores::MetricHelper.active_record_product_name_from_adapter("MySQL")
        assert_equal "MySQL", product_name
      end

      def test_product_is_named_properly_for_mysql2_adapter
        product_name = Datastores::MetricHelper.active_record_product_name_from_adapter("Mysql2")
        assert_equal "MySQL", product_name
      end

      def test_product_is_named_properly_for_postgres_adapter
        product_name = Datastores::MetricHelper.active_record_product_name_from_adapter("PostgreSQL")
        assert_equal "Postgres", product_name
      end

      def test_product_is_named_properly_for_sqlite_adapter
        product_name = Datastores::MetricHelper.active_record_product_name_from_adapter("SQLite")
        assert_equal "SQLite", product_name
      end

      def test_product_is_active_record_for_unkown_adapter
        product_name = Datastores::MetricHelper.active_record_product_name_from_adapter("YouDontKnowThisAdapter")
        assert_equal "ActiveRecord", product_name
      end
    end
  end
end
