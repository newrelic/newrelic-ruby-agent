# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

SimpleCovHelper.command_name "test:multiverse[mongo]"
require 'mongo'
require 'newrelic_rpm'
require 'new_relic/agent/datastores/mongo'

if NewRelic::Agent::Datastores::Mongo.is_supported_version? &&
    !NewRelic::Agent::Datastores::Mongo.is_monitoring_enabled?
  require File.join(File.dirname(__FILE__), '..', '..', '..', 'helpers', 'mongo_metric_builder')
  require File.join(File.dirname(__FILE__), 'helpers', 'mongo_server')
  require File.join(File.dirname(__FILE__), 'helpers', 'mongo_replica_set')
  require File.join(File.dirname(__FILE__), 'helpers', 'mongo_operation_tests')

  class NewRelic::Agent::Instrumentation::MongoConnectionTest
    include Mongo
    include ::NewRelic::TestHelpers::MongoMetricBuilder
    include ::MongoOperationTests

    def setup
      @client = Mongo::Connection.new($mongo.host, $mongo.port)
      @database_name = "multiverse"
      @database = @client.db(@database_name)
      @collection_name = "tribbles-#{fake_guid(16)}"
      @collection = @database.collection(@collection_name)

      @tribble = {'name' => 'soterios johnson'}

      NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(true)
      NewRelic::Agent.drop_buffered_data
    end

    def teardown
      NewRelic::Agent.drop_buffered_data
      @database.drop_collection(@collection_name)
    end
  end
end
