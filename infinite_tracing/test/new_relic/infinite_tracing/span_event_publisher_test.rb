# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)

module NewRelic
  module Agent
    module InfiniteTracing
      class SpanEventPublisherTest < Minitest::Test
        include FakeTraceObserverHelpers

        # NOTE: intentionally overriding FakeTraceObserverHelpers setup
        def setup
          @additional_config = localhost_config
          NewRelic::Agent.config.add_config_for_testing(@additional_config)
          NewRelic::Agent.config.notify_server_source_added

          nr_freeze_time
        end

        # NOTE: intentionally overriding FakeTraceObserverHelpers teardown
        def teardown
          NewRelic::Agent.config.remove_config(@additional_config)
          NewRelic::Agent.drop_buffered_data
        end

        def test_non_sampled_segment_does_not_record_span_event
          with_config localhost_config do
            in_web_transaction('wat') do |txn|
              txn.stubs(:sampled?).returns(false)

              segment = Tracer.start_datastore_segment(
                product: "SQLite",
                operation: "select",
                port_path_or_id: 1337807
              )

              segment.start
              advance_time 1.0
              segment.finish
            end

            last_span_events = NewRelic::Agent.agent.span_event_aggregator.harvest![1]
            assert_empty last_span_events
          end
        end

        def test_sampled_segment_records_span_event
          with_config localhost_config do
            trace_id      = nil
            txn_guid      = nil
            sampled       = nil
            priority      = nil
            timestamp     = nil
            sql_statement = "select * from table"

            in_web_transaction('wat') do |txn|
              txn.stubs(:sampled?).returns(true)

              segment = Tracer.start_datastore_segment(
                product: "SQLite",
                collection: "Blahg",
                operation: "select",
                host: "rachel.foo",
                port_path_or_id: 1337807,
                database_name: "calzone_zone",
              )

              segment.notice_sql sql_statement
              advance_time 1
              segment.finish

              timestamp = Integer(segment.start_time.to_f * 1000.0)

              trace_id = txn.trace_id
              txn_guid = txn.guid
              sampled  = txn.sampled?
              priority = txn.priority
            end

            last_span_events  = NewRelic::Agent.agent.span_event_aggregator.harvest![1]
            assert_equal 2, last_span_events.size
            intrinsics, _, agent_attributes = last_span_events[0]
            root_span_event   = last_span_events[1][0]
            root_guid         = root_span_event['guid']

            datastore = 'Datastore/statement/SQLite/Blahg/select'

            assert_equal 'Span',      intrinsics.fetch('type')
            assert_equal trace_id,    intrinsics.fetch('traceId')
            refute_nil                intrinsics.fetch('guid')
            assert_equal root_guid,   intrinsics.fetch('parentId')
            assert_equal txn_guid,    intrinsics.fetch('transactionId')
            assert_equal sampled,     intrinsics.fetch('sampled')
            assert_equal priority,    intrinsics.fetch('priority')
            assert_equal timestamp,   intrinsics.fetch('timestamp')
            assert_equal 1.0,         intrinsics.fetch('duration')
            assert_equal datastore,   intrinsics.fetch('name')
            assert_equal 'datastore', intrinsics.fetch('category')
            assert_equal 'SQLite',    intrinsics.fetch('component')
            assert_equal 'client',    intrinsics.fetch('span.kind')

            assert_equal 'calzone_zone',       agent_attributes.fetch('db.instance')
            assert_equal 'rachel.foo:1337807', agent_attributes.fetch('peer.address')
            assert_equal 'rachel.foo',         agent_attributes.fetch('peer.hostname')
            assert_equal sql_statement,        agent_attributes.fetch('db.statement')
          end
        end

        private

        def generate_event(name='operation_name', options = {})
          guid = fake_guid(16)

          event = [
            {
            'name' => name,
            'priority' => options[:priority] || rand,
            'sampled' => false,
            'guid'    => guid,
            'traceId' => guid,
            'timestamp' => (Time.now.to_f * 1000).round,
            'duration' => rand,
            'category' => 'custom'
            },
            {},
            {}
          ]

          @event_publisher.record event: event
        end

      end
    end
  end
end