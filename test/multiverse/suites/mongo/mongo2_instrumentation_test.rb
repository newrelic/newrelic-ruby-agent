# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'mongo'
require 'newrelic_rpm'
require 'new_relic/agent/datastores/mongo'
require 'helpers/mongo_metric_builder'

if NewRelic::Agent::Datastores::Mongo.is_supported_version? &&
    NewRelic::Agent::Datastores::Mongo.is_monitoring_enabled?

  require File.join(File.dirname(__FILE__), 'helpers', 'mongo_helpers')

  module NewRelic
    module Agent
      module Instrumentation
        class Mongo2InstrumentationTest < Minitest::Test
          include Mongo
          include TestHelpers::MongoMetricBuilder
          include NewRelic::MongoHelpers

          def setup
            Mongo::Logger.logger = mongo_logger
            @database_name = "multiverse"
            @client = Mongo::Client.new(
              ["#{$mongo.host}:#{$mongo.port}"], 
              database: @database_name
            )
            @database = @client.database

            @collection_name = "tribbles-#{fake_guid(16)}"
            @collection = @database.collection(@collection_name)

            @tribbles = [{'name' => 'soterios johnson', 'count' => 1}, {'name' => 'wes mantooth', 'count' => 2}]
            @tribble = {:_id => 1, 'name' => 'soterios johnson'}

            NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(true)
            NewRelic::Agent.drop_buffered_data
          end

          def teardown
            NewRelic::Agent.drop_buffered_data
            @collection.drop
          end

          def test_noticed_error_at_segment_and_txn_when_violating_unique_contraints
            expected_error_class = /Mongo\:\:Error/
            txn = nil
            begin
              in_transaction do |db_txn|
                txn = db_txn
                @collection.insert_one(@tribble)
                @collection.insert_one(@tribble)
              end
            rescue StandardError => e
              # NOP -- allowing span and transaction to notice error
            end

            assert_segment_noticed_error txn, /insert/i, expected_error_class, /duplicate key error/i
            assert_transaction_noticed_error txn, expected_error_class
          end

          def test_noticed_error_only_at_segment_when_violating_unique_constraints
            expected_error_class = /Mongo\:\:Error/
            txn = nil
            in_transaction do |db_txn|
              begin
                txn = db_txn
                @collection.insert_one(_id: 1)
                @collection.insert_one(_id: 1)
              rescue Mongo::Error::OperationFailure => e
                # NOP -- allowing ONLY span to notice error
              end
            end

            assert_segment_noticed_error txn, /insert/i, expected_error_class, /duplicate key error/i
            refute_transaction_noticed_error txn, expected_error_class
          end

          def test_noticed_error_only_at_segment_when_command_fails
            expected_error_class = /Mongo\:\:Error/
            txn = nil
            in_transaction do |db_txn|
              begin
                txn = db_txn
                @database.collection("bogus").drop
              rescue Mongo::Error::OperationFailure => e
                # NOP -- allowing ONLY span to notice error
              end
            end
            assert_segment_noticed_error txn, /bogus\/drop/i, expected_error_class, /ns not found/i
            refute_transaction_noticed_error txn, expected_error_class
          end

          def test_records_metrics_for_insert_one
            in_transaction do
              @collection.insert_one(@tribbles.first)
            end

            metrics = build_test_metrics(:insert, true)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_insert_many
            in_transaction do
              @collection.insert_many(@tribbles)
            end

            metrics = build_test_metrics(:insert, true)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_delete_one
            @collection.insert_one(@tribbles.first)
            NewRelic::Agent.drop_buffered_data

            in_transaction do
              @collection.delete_one(@tribbles.first)
            end

            metrics = build_test_metrics(:delete, true)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_delete_many
            @collection.insert_one(@tribbles.first)
            NewRelic::Agent.drop_buffered_data

            in_transaction do
              @collection.delete_many(@tribbles.first)
            end

            metrics = build_test_metrics(:delete, true)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_replace_one
            @collection.insert_one(@tribbles.first)
            NewRelic::Agent.drop_buffered_data

            in_transaction do
              @collection.replace_one(@tribbles[0], @tribbles[1])
            end

            metrics = build_test_metrics(:update, true)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_update_one
            @collection.insert_one(@tribbles.first)
            NewRelic::Agent.drop_buffered_data

            in_transaction do
              @collection.update_one(@tribbles[0], "$set" => @tribbles[1])
            end

            metrics = build_test_metrics(:update, true)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_update_many
            @collection.insert_one(@tribbles.first)
            NewRelic::Agent.drop_buffered_data

            in_transaction do
              @collection.update_many(@tribbles[0], "$set" => @tribbles[1])
            end

            metrics = build_test_metrics(:update, true)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_find
            @collection.insert_one(@tribbles.first)
            NewRelic::Agent.drop_buffered_data

            in_transaction do
              @collection.find(@tribbles.first).to_a
            end

            metrics = build_test_metrics(:find, true)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_find_one_and_delete
            @collection.insert_one(@tribbles.first)
            NewRelic::Agent.drop_buffered_data

            in_transaction do
              @collection.find_one_and_delete(@tribbles.first)
            end

            metrics = build_test_metrics(:findAndModify, true)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_find_one_and_replace
            @collection.insert_one(@tribbles.first)
            NewRelic::Agent.drop_buffered_data

            in_transaction do
              @collection.find_one_and_replace(@tribbles[0], @tribbles[1])
            end

            metrics = build_test_metrics(:findAndModify, true)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_find_one_and_update
            @collection.insert_one(@tribbles.first)
            NewRelic::Agent.drop_buffered_data

            in_transaction do
              @collection.find_one_and_update(@tribbles[0], "$set" => @tribbles[1])
            end

            metrics = build_test_metrics(:findAndModify, true)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_distinct
            in_transaction do
              @collection.distinct('name')
            end

            metrics = build_test_metrics(:distinct, true)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_count
            in_transaction do
              @collection.count
            end

            metrics = build_test_metrics(:count, true)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_records_metrics_for_aggregate
            in_transaction do
              @collection.aggregate([
                {'$group' => {'_id' => "name", "max" => {'$max'=>"$count"}}},
                {'$match' => {'max' => {'$gte' => 1}}}
              ]).to_a
            end

            metrics = build_test_metrics(:aggregate, true)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_aggregate_pipeline_obfuscated_by_default
            in_transaction do
              @collection.aggregate([
                {'$group' => {'_id' => "name", "max" => {'$max'=>"$count"}}},
                {'$match' => {'max' => {'$gte' => 1}}}
              ]).to_a
            end

            sample = last_transaction_trace
            metric = "Datastore/statement/MongoDB/#{@collection_name}/aggregate"
            node = find_node_with_name(sample, metric)

            expected = [
              {"$group"=>{"_id"=>"?", "max"=>{"$max"=>"?"}}},
              {"$match"=>{"max"=>{"$gte"=>"?"}}}
            ]

            assert_equal expected, node[:statement]["pipeline"]
          end

          def test_filter_obfuscated_by_default
            in_transaction do
              @collection.find("name" => "Wes Mantooth", "count" => {"$gte" => 1}).to_a
            end

            sample = last_transaction_trace
            metric = "Datastore/statement/MongoDB/#{@collection_name}/find"
            node = find_node_with_name(sample, metric)

            expected = {"name"=>"?", "count"=>{"$gte"=>"?"}}

            assert_equal expected, node[:statement]["filter"]
          end

          def test_batched_queries
            25.times do |i|
              @collection.insert_one :name => "test-#{i}", :active => true
            end
            NewRelic::Agent.drop_buffered_data

            in_transaction("test_txn") do
              @collection.find(:active => true).batch_size(10).to_a
            end

            expected = {
              "test_txn" => {:call_count=>1},
              "OtherTransactionTotalTime" => {:call_count=>1},
              "OtherTransactionTotalTime/test_txn" => {:call_count=>1},
              ["Datastore/statement/MongoDB/#{@collection_name}/find", "test_txn"] => {:call_count=>1},
              "Datastore/statement/MongoDB/#{@collection_name}/find" => {:call_count=>1},
              ["Datastore/statement/MongoDB/#{@collection_name}/getMore", "test_txn"] => {:call_count=>2},
              "Datastore/statement/MongoDB/#{@collection_name}/getMore" => {:call_count=>2},
              "Datastore/operation/MongoDB/find" => {:call_count=>1},
              "Datastore/operation/MongoDB/getMore" => {:call_count=>2},
              "Datastore/instance/MongoDB/#{NewRelic::Agent::Hostname.get}/27017" => {:call_count=>3},
              "Datastore/MongoDB/allWeb" => {:call_count=>3},
              "Datastore/MongoDB/all" => {:call_count=>3},
              "Datastore/allWeb" => { :call_count=>3},
              "Datastore/all" => {:call_count=>3},
              "Supportability/API/drop_buffered_data" => { :call_count => 1 }
            }
            assert_metrics_recorded_exclusive expected
          end

          def test_batched_queries_have_node_per_query
            25.times do |i|
              @collection.insert_one :name => "test-#{i}", :active => true
            end
            NewRelic::Agent.drop_buffered_data
            in_transaction "webby" do
              @collection.find(:active => true).batch_size(10).to_a
            end

            expected = [
              "Datastore/statement/MongoDB/#{@collection_name}/find",
              "Datastore/statement/MongoDB/#{@collection_name}/getMore",
              "Datastore/statement/MongoDB/#{@collection_name}/getMore"
            ]

            trace = last_transaction_trace
            actual = []
            trace.each_node do |n|
              actual << n.metric_name if n.metric_name.start_with? "Datastore/statement/MongoDB"
            end

            assert_equal expected, actual
          end

          def test_trace_nodes_have_instance_attributes
            @collection.insert_one :name => "test", :active => true
            NewRelic::Agent.drop_buffered_data
            in_transaction "webby" do
              @collection.find(:active => true).to_a
            end

            trace = last_transaction_trace
            node = find_node_with_name_matching trace, /^Datastore\//

            assert_equal NewRelic::Agent::Hostname.get, node[:host]
            assert_equal '27017', node[:port_path_or_id]
            assert_equal @database_name, node[:database_name]
          end

          def test_drop_collection
            in_transaction do
              @collection.drop
            end

            metrics = build_test_metrics(:drop, true)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_web_scoped_metrics
            in_web_transaction("webby") do
              @collection.insert_one(@tribbles.first)
            end

            metric = statement_metric(:insert)
            assert_metrics_recorded([[metric, "webby"]])
          end

          def test_background_scoped_metrics
            in_background_transaction("backed-up") do
              @collection.insert_one(@tribbles.first)
            end

            metric = statement_metric(:insert)
            assert_metrics_recorded([[metric, "backed-up"]])
          end

          def test_notices_nosql
            node = nil

            in_transaction do
              @collection.insert_one(@tribbles.first)
            end

            node = find_last_transaction_node

            expected = {
              :database   => @database_name,
              :collection => @collection_name,
              'insert' => @collection_name,
              :operation  => :insert,
              'ordered' => true
            }

            result = node.params[:statement]

            # Depending on the Mongo DB version, we may get back
            # strings instead of symbols.  Let's adjust our
            # expectations accordingly.
            #
            if result[:operation].is_a?(String)
              expected[:operation] = expected[:operation].to_s
            end

            # The writeConcern is added by some, but not all versions
            # of the mongo driver, we don't care if it's present or
            # not, just that the statement is noticed
            #
            result.delete('writeConcern')

            if expected.is_a?(String)
              assert_equal expected, result
            else
              expected.each do |key, value|
                assert_equal value, result[key]
              end
            end
          end

          def test_noticed_nosql_includes_operation
            node = nil

            in_transaction do
              @collection.insert_one(@tribbles.first)
            end

            node = find_last_transaction_node
            query = node.params[:statement]

            assert_mongo_operation :insert, query
          end

          def test_noticed_nosql_includes_update_one_operation
            node = nil

            in_transaction do
              @collection.update_one(@tribbles[0], @tribbles[1])
            end

            node = find_last_transaction_node
            query = node.params[:statement]

            assert_mongo_operation :update, query
          end

          def test_noticed_nosql_includes_find_operation
            node = nil

            in_transaction do
              @collection.insert_one(@tribbles.first)
              @collection.find(@tribbles.first).to_a
            end

            node = find_last_transaction_node
            query = node.params[:statement]

            assert_mongo_operation 'find', query
          end

          def test_noticed_nosql_does_not_contain_documents
            node = nil

            in_transaction do
              @collection.insert_one(@tribbles.first)
            end

            node = find_last_transaction_node
            statement = node.params[:statement]

            refute statement.keys.include?(:documents), "Noticed NoSQL should not include documents: #{statement}"
          end

          def test_noticed_nosql_does_not_contain_selector_values
            @collection.insert_one({'password' => '$ecret'})
            node = nil

            in_transaction do
              @collection.find({'password' => '$ecret'}).to_a
            end

            node = find_last_transaction_node
            statement = node.params[:statement]

            refute statement.inspect.include?('$ecret')
            assert_equal '?', statement['filter']['password']
          end

          def test_web_requests_record_all_web_metric
            NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(true)
            in_web_transaction do
              @collection.insert_one(@tribbles.first)
            end

            metrics = build_test_metrics(:insert, true)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_web_requests_do_not_record_all_other_metric
            NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(true)
            in_background_transaction do
              @collection.insert_one(@tribbles.first)
            end

            assert_metrics_not_recorded(['Datastore/allOther'])
          end

          def test_other_requests_record_all_other_metric
            NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(false)
            in_transaction do
              @collection.insert_one(@tribbles.first)
            end

            metrics = build_test_metrics(:insert, true)
            expected = metrics_with_attributes(metrics)

            assert_metrics_recorded(expected)
          end

          def test_other_requests_do_not_record_all_web_metric
            NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(false)
            @collection.insert_one(@tribbles.first)

            assert_metrics_not_recorded(['Datastore/allWeb'])
          end

          def statement_metric(action)
            metrics = build_test_metrics(action, true)
            metrics.select { |m| m.start_with?("Datastore/statement") }.first
          end

          def assert_mongo_operation(expected_value, query)
            assert_equal expected_value.to_s, query[:operation].to_s
          end
        end
      end
    end
  end
end
