# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'mongo'
require 'newrelic_rpm'
require 'new_relic/agent/datastores/mongo'
require File.join(File.dirname(__FILE__), '..', '..', '..', 'agent_helper')

if !NewRelic::Agent::Datastores::Mongo.is_supported_version?
  require File.join(File.dirname(__FILE__), 'helpers', 'mongo_server')

  class NewRelic::Agent::Instrumentation::MongoInstrumentationTest < Minitest::Test
    include Mongo

    def setup
      @client = Mongo::Connection.new($mongo.host, $mongo.port)
      @database_name = "multiverse"
      @database = @client.db(@database_name)
      @collection_name = "tribbles-#{SecureRandom.hex(16)}"
      @collection = @database.collection(@collection_name)

      @tribble = {'name' => 'soterios johnson'}

      NewRelic::Agent.drop_buffered_data
    end

    def teardown
      NewRelic::Agent.drop_buffered_data
      @database.drop_collection(@collection_name)
    end

    def test_records_metrics_for_insert
      @collection.insert(@tribble)
      assert_metrics_not_recorded(["Datastore/all", "Datastore/allWeb", "Datastore/allOther"])
    end
  end
end
