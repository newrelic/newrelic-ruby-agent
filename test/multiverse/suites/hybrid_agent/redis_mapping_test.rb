# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        class RedisMappingTest < Minitest::Test
          def setup
            @tracer = NewRelic::Agent::OpenTelemetry::Trace::Tracer.new('opentelemetry-instrumentation-redis')
            harvest_span_events!
            harvest_transaction_events!
          end

          def teardown
            mocha_teardown
          end

          def redis_v_1_17_attrs
            {
              'db.system' => 'redis',
              'db.operation' => 'GET',
              'db.name' => 'customers',
              'db.statement' => 'SET user:42 some-secret',
              'db.user' => 'default',
              'net.peer.name' => 'redis.example',
              'net.peer.port' => '6379'
            }
          end

          def redis_v_1_25_attrs
            {
              'db.system.name' => 'redis',
              'db.operation.name' => 'GET',
              'db.query.text' => 'SET user:42 some-secret',
              'db.user' => 'default',
              'server.address' => 'redis.example',
              'server.port' => '6379'
            }
          end

          def start_redis_client_segment(attrs)
            in_transaction(category: :web) do |txn|
              txn.stubs(:sampled?).returns(true)

              @tracer.in_span('GET', attributes: attrs.dup, kind: :client) do |span|
                # noop
              end
            end
          end

          def test_redis_v_1_17_segment_properties
            transaction = start_redis_client_segment(redis_v_1_17_attrs)

            segment = transaction.segments[1]

            assert_instance_of NewRelic::Agent::Transaction::DatastoreSegment, segment

            assert_equal 'Datastore/operation/redis/GET', segment.name
            assert_equal redis_v_1_17_attrs['net.peer.name'], segment.host
          end

          def test_redis_v_1_17_metrics
            start_redis_client_segment(redis_v_1_17_attrs)

            assert_metrics_recorded([
              'Datastore/all',
              'Datastore/allWeb',
              'Datastore/instance/redis/redis.example/6379',
              'Datastore/operation/redis/GET',
              'Datastore/redis/all'
            ])
          end

          def test_redis_v_1_17_intrinsic_attributes
            start_redis_client_segment(redis_v_1_17_attrs)

            spans = harvest_span_events!
            span = spans[1][0]
            intrinsics = span[0]

            assert_equal redis_v_1_17_attrs['db.system'], intrinsics['component']
            assert_equal 'client', intrinsics['span.kind']
            assert_equal 'datastore', intrinsics['category']
          end

          def test_redis_v_1_17_agent_attributes
            start_redis_client_segment(redis_v_1_17_attrs)

            spans = harvest_span_events!
            span = spans[1][0]
            agent = span[2]

            assert_equal redis_v_1_17_attrs['db.name'], agent['db.instance']
            assert_equal "#{redis_v_1_17_attrs['net.peer.name']}:#{redis_v_1_17_attrs['net.peer.port']}", agent['peer.address']
            assert_equal redis_v_1_17_attrs['net.peer.name'], agent['peer.hostname']
            assert_equal redis_v_1_17_attrs['net.peer.name'], agent['server.address']
            assert_equal redis_v_1_17_attrs['net.peer.port'], agent['server.port']
            assert_equal redis_v_1_17_attrs['db.system'], agent['db.system']
            # statement comes through via notice_nosql_statement (not SQL-obfuscated)
            assert_equal redis_v_1_17_attrs['db.statement'], agent['db.statement']
          end

          def test_redis_v_1_17_custom_attributes
            start_redis_client_segment(redis_v_1_17_attrs)

            spans = harvest_span_events!
            span = spans[1][0]
            custom = span[1]

            keys_assigned_elsewhere = %w[db.system db.name db.operation net.peer.name net.peer.port db.statement]

            assert_empty custom.keys & keys_assigned_elsewhere
            assert_equal redis_v_1_17_attrs['db.user'], custom['db.user']
          end

          def test_redis_v_1_25_segment_properties
            transaction = start_redis_client_segment(redis_v_1_25_attrs)

            segment = transaction.segments[1]

            assert_instance_of NewRelic::Agent::Transaction::DatastoreSegment, segment

            assert_equal 'Datastore/operation/redis/GET', segment.name
            assert_equal redis_v_1_25_attrs['server.address'], segment.host
          end

          def test_redis_v_1_25_metrics
            start_redis_client_segment(redis_v_1_25_attrs)

            assert_metrics_recorded([
              'Datastore/all',
              'Datastore/allWeb',
              'Datastore/instance/redis/redis.example/6379',
              'Datastore/operation/redis/GET',
              'Datastore/redis/all'
            ])
          end

          def test_redis_v_1_25_intrinsic_attributes
            start_redis_client_segment(redis_v_1_25_attrs)

            spans = harvest_span_events!
            span = spans[1][0]
            intrinsics = span[0]

            assert_equal redis_v_1_25_attrs['db.system.name'], intrinsics['component']
            assert_equal 'client', intrinsics['span.kind']
            assert_equal 'datastore', intrinsics['category']
          end

          def test_redis_v_1_25_agent_attributes
            start_redis_client_segment(redis_v_1_25_attrs)

            spans = harvest_span_events!
            span = spans[1][0]
            agent = span[2]

            assert_equal "#{redis_v_1_25_attrs['server.address']}:#{redis_v_1_25_attrs['server.port']}", agent['peer.address']
            assert_equal redis_v_1_25_attrs['server.address'], agent['peer.hostname']
            assert_equal redis_v_1_25_attrs['server.address'], agent['server.address']
            assert_equal redis_v_1_25_attrs['server.port'], agent['server.port']
            assert_equal redis_v_1_25_attrs['db.system.name'], agent['db.system']
            # statement comes through via notice_nosql_statement (not SQL-obfuscated)
            assert_equal redis_v_1_25_attrs['db.query.text'], agent['db.statement']
          end

          def test_redis_v_1_25_custom_attributes
            start_redis_client_segment(redis_v_1_25_attrs)

            spans = harvest_span_events!
            span = spans[1][0]
            custom = span[1]

            keys_assigned_elsewhere = %w[db.system.name db.operation.name db.query.text server.address server.port]

            assert_empty custom.keys & keys_assigned_elsewhere
            assert_equal redis_v_1_25_attrs['db.user'], custom['db.user']
          end
        end
      end
    end
  end
end
