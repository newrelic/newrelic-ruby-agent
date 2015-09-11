# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'mongo'
require 'newrelic_rpm'
require 'new_relic/agent/datastores/mongo'

if !NewRelic::Agent::Datastores::Mongo.is_supported_version?
  class NewRelic::Agent::Instrumentation::MongoInstrumentationTest < Minitest::Test
    include Mongo

    def setup
      @database_name = "multiverse"
      @collection_name = "tribbles-#{SecureRandom.hex(16)}"
      @tribble = {'name' => 'soterios johnson'}

      setup_collection

      NewRelic::Agent.drop_buffered_data
    end

    def teardown
      NewRelic::Agent.drop_buffered_data
      drop_collection
    end

    def test_records_metrics_for_insert
      insert_to_collection
      assert_metrics_not_recorded(["Datastore/all", "Datastore/allWeb", "Datastore/allOther"])
    end

    # API changes between 1.x and 2.x that we need to work around to make
    # sure that we're testing unsupported versions properly
    module Mongo1xUnsupported
      def setup_collection
        client = Mongo::Connection.new($mongo.host, $mongo.port)
        @database = client.db(@database_name)
        @collection = @database.collection(@collection_name)
      end

      def drop_collection
        @database.drop_collection(@collection_name)
      end

      def insert_to_collection
        @collection.insert(@tribble)
      end
    end

    module Mongo2xUnsupported
      def setup_collection
        client = Mongo::Client.new(["#{$mongo.host}:#{$mongo.port}"], :database => @database_name, :connect => :direct)
        @collection = client[@collection_name]
      end

      def drop_collection
        @collection.drop
      end

      def insert_to_collection
        @collection.insert_one(@tribble)
      end
    end

    if NewRelic::Agent::Datastores::Mongo.is_unsupported_2x?
      include Mongo2xUnsupported
    else
      include Mongo1xUnsupported
    end
  end
end
