# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'mongo'
require 'newrelic_rpm'
require 'new_relic/agent/datastores/mongo'
require 'helpers/mongo_metric_builder'

if NewRelic::Agent::Datastores::Mongo.is_supported_version? &&
    NewRelic::Agent::Datastores::Mongo.is_monitoring_enabled?
  module NewRelic
    module Agent
      module Instrumentation
        class Mongo2InstrumentationTest < Minitest::Test
          include Mongo
          include TestHelpers::MongoMetricBuilder

          def setup
            @client = Mongo::Client.new(["#{$mongo.host}:#{$mongo.port}"])
            @database_name = "multiverse"
            @client.use(@database_name)
            @database = @client.database

            @collection_name = "tribbles-#{SecureRandom.hex(16)}"
            @collection = @database.collection(@collection_name)

            @tribble = {'name' => 'soterios johnson'}

            NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(true)
            NewRelic::Agent.drop_buffered_data
          end

          def teardown
            NewRelic::Agent.drop_buffered_data
            @collection.drop
          end

          def test_records_metrics_for_insert
            @collection.insert_one(@tribble)

            metrics = build_test_metrics(:insert)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          # def test_records_metrics_for_find
          #   @collection.insert_one(@tribble)
          #   NewRelic::Agent.drop_buffered_data

          #   @collection.find(@tribble).to_a

          #   metrics = build_test_metrics(:find)
          #   expected = metrics_with_attributes(metrics)

          #   assert_metrics_recorded(expected)
          # end
        end
      end
    end
  end
end