# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        class MongoMappingTest < Minitest::Test
          def setup
            @tracer = NewRelic::Agent::OpenTelemetry::Trace::Tracer.new('opentelemetry-instrumentation-mongo')
            harvest_span_events!
            harvest_transaction_events!
          end

          def teardown
            mocha_teardown
          end

          def mongo_v_1_17_attrs
            {
              'db.system' => 'mongodb',
              'db.operation' => 'find',
              'db.name' => 'customers',
              'db.statement' => '{"find":"users","filter":{"_id":42}}',
              'db.mongodb.collection' => 'users',
              'db.user' => 'admin',
              'net.peer.name' => 'mongodb.example',
              'net.peer.port' => '27017'
            }
          end

          def mongo_v_1_25_attrs
            {
              'db.system.name' => 'mongodb',
              'db.operation.name' => 'find',
              'db.namespace' => 'customers',
              'db.query.text' => '{"find":"users","filter":{"_id":42}}',
              'db.collection.name' => 'users',
              'db.user' => 'admin',
              'server.address' => 'mongodb.example',
              'server.port' => '27017'
            }
          end

          def start_mongo_client_segment(attrs)
            in_transaction(category: :web) do |txn|
              txn.stubs(:sampled?).returns(true)

              @tracer.in_span('find', attributes: attrs.dup, kind: :client) do |span|
                # noop
              end
            end
          end

          def test_mongo_v_1_17_segment_properties
            transaction = start_mongo_client_segment(mongo_v_1_17_attrs)

            segment = transaction.segments[1]

            assert_instance_of NewRelic::Agent::Transaction::DatastoreSegment, segment

            assert_equal 'Datastore/statement/mongodb/users/find', segment.name
            assert_equal mongo_v_1_17_attrs['net.peer.name'], segment.host
            assert_equal mongo_v_1_17_attrs['db.mongodb.collection'], segment.collection
          end

          def test_mongo_v_1_17_metrics
            start_mongo_client_segment(mongo_v_1_17_attrs)

            assert_metrics_recorded([
              'Datastore/all',
              'Datastore/allWeb',
              'Datastore/instance/mongodb/mongodb.example/27017',
              'Datastore/statement/mongodb/users/find',
              'Datastore/operation/mongodb/find',
              'Datastore/mongodb/all'
            ])
          end

          def test_mongo_v_1_17_intrinsic_attributes
            start_mongo_client_segment(mongo_v_1_17_attrs)

            spans = harvest_span_events!
            span = spans[1][0]
            intrinsics = span[0]

            assert_equal mongo_v_1_17_attrs['db.system'], intrinsics['component']
            assert_equal 'client', intrinsics['span.kind']
            assert_equal 'datastore', intrinsics['category']
          end

          def test_mongo_v_1_17_agent_attributes
            start_mongo_client_segment(mongo_v_1_17_attrs)

            spans = harvest_span_events!
            span = spans[1][0]
            agent = span[2]

            assert_equal mongo_v_1_17_attrs['db.name'], agent['db.instance']
            assert_equal "#{mongo_v_1_17_attrs['net.peer.name']}:#{mongo_v_1_17_attrs['net.peer.port']}", agent['peer.address']
            assert_equal mongo_v_1_17_attrs['net.peer.name'], agent['peer.hostname']
            assert_equal mongo_v_1_17_attrs['net.peer.name'], agent['server.address']
            assert_equal mongo_v_1_17_attrs['net.peer.port'], agent['server.port']
            assert_equal mongo_v_1_17_attrs['db.system'], agent['db.system']
            # statement comes through via notice_nosql_statement (not SQL-obfuscated)
            assert_equal mongo_v_1_17_attrs['db.statement'], agent['db.statement']
          end

          def test_mongo_v_1_17_custom_attributes
            start_mongo_client_segment(mongo_v_1_17_attrs)

            spans = harvest_span_events!
            span = spans[1][0]
            custom = span[1]

            keys_assigned_elsewhere = %w[db.system db.name db.operation db.statement db.mongodb.collection net.peer.name net.peer.port]

            assert_empty custom.keys & keys_assigned_elsewhere
            assert_equal mongo_v_1_17_attrs['db.user'], custom['db.user']
          end

          def test_mongo_v_1_25_segment_properties
            transaction = start_mongo_client_segment(mongo_v_1_25_attrs)

            segment = transaction.segments[1]

            assert_instance_of NewRelic::Agent::Transaction::DatastoreSegment, segment

            assert_equal 'Datastore/statement/mongodb/users/find', segment.name
            assert_equal mongo_v_1_25_attrs['server.address'], segment.host
            assert_equal mongo_v_1_25_attrs['db.collection.name'], segment.collection
          end

          def test_mongo_v_1_25_metrics
            start_mongo_client_segment(mongo_v_1_25_attrs)

            assert_metrics_recorded([
              'Datastore/all',
              'Datastore/allWeb',
              'Datastore/instance/mongodb/mongodb.example/27017',
              'Datastore/statement/mongodb/users/find',
              'Datastore/operation/mongodb/find',
              'Datastore/mongodb/all'
            ])
          end

          def test_mongo_v_1_25_intrinsic_attributes
            start_mongo_client_segment(mongo_v_1_25_attrs)

            spans = harvest_span_events!
            span = spans[1][0]
            intrinsics = span[0]

            assert_equal mongo_v_1_25_attrs['db.system.name'], intrinsics['component']
            assert_equal 'client', intrinsics['span.kind']
            assert_equal 'datastore', intrinsics['category']
          end

          def test_mongo_v_1_25_agent_attributes
            start_mongo_client_segment(mongo_v_1_25_attrs)

            spans = harvest_span_events!
            span = spans[1][0]
            agent = span[2]

            assert_equal mongo_v_1_25_attrs['db.namespace'], agent['db.instance']
            assert_equal "#{mongo_v_1_25_attrs['server.address']}:#{mongo_v_1_25_attrs['server.port']}", agent['peer.address']
            assert_equal mongo_v_1_25_attrs['server.address'], agent['peer.hostname']
            assert_equal mongo_v_1_25_attrs['server.address'], agent['server.address']
            assert_equal mongo_v_1_25_attrs['server.port'], agent['server.port']
            assert_equal mongo_v_1_25_attrs['db.system.name'], agent['db.system']
            # statement comes through via notice_nosql_statement (not SQL-obfuscated)
            assert_equal mongo_v_1_25_attrs['db.query.text'], agent['db.statement']
          end

          def test_mongo_v_1_25_custom_attributes
            start_mongo_client_segment(mongo_v_1_25_attrs)

            spans = harvest_span_events!
            span = spans[1][0]
            custom = span[1]

            keys_assigned_elsewhere = %w[db.system.name db.operation.name db.namespace db.query.text db.collection.name server.address server.port]

            assert_empty custom.keys & keys_assigned_elsewhere
            assert_equal mongo_v_1_25_attrs['db.user'], custom['db.user']
          end
        end
      end
    end
  end
end
