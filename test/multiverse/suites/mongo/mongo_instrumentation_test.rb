# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'mongo'
require 'newrelic_rpm'
require 'new_relic/agent/datastores/mongo'
require 'securerandom'

if NewRelic::Agent::Datastores::Mongo.is_supported_version? &&
    !NewRelic::Agent::Datastores::Mongo.is_monitoring_enabled?
  require File.join(File.dirname(__FILE__), '..', '..', '..', 'helpers', 'mongo_metric_builder')
  require File.join(File.dirname(__FILE__), 'helpers', 'mongo_server')
  require File.join(File.dirname(__FILE__), 'helpers', 'mongo_replica_set')
  require File.join(File.dirname(__FILE__), 'helpers', 'mongo_operation_tests')

  class NewRelic::Agent::Instrumentation::MongoInstrumentationTest < Minitest::Test
    include Mongo
    include ::NewRelic::TestHelpers::MongoMetricBuilder
    include ::MongoOperationTests

    def setup
      @client = Mongo::MongoClient.new($mongo.host, $mongo.port)
      @database_name = "multiverse"
      @database = @client.db(@database_name)
      @collection_name = "tribbles-#{SecureRandom.hex(16)}"
      @collection = @database.collection(@collection_name)

      @tribble = {'name' => 'soterios johnson'}

      NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(true)
      NewRelic::Agent.drop_buffered_data
    end

    def test_mongo_query_succeeds_if_metric_generation_fails
      NewRelic::Agent::Datastores::Mongo::MetricTranslator.stubs(:operation_and_collection_for).returns(nil)
      result = @collection.insert(@tribble)
      refute_nil result
    end

    def test_ensure_index_succeeds_if_metric_generation_fails
      NewRelic::Agent::Datastores::Mongo::MetricTranslator.stubs(:operation_and_collection_for).returns(nil)
      result = @collection.ensure_index(:"field#{SecureRandom.hex(10)}")
      refute_nil result
    end

    def test_records_metrics_for_save
      NewRelic::Agent::Datastores::Mongo::MetricTranslator.stubs(:operation_and_collection_for).returns(nil)
      result = @collection.save(@tribble)
      refute_nil result
    end

    def teardown
      NewRelic::Agent.drop_buffered_data
      @database.drop_collection(@collection_name)
    end
  end
end
