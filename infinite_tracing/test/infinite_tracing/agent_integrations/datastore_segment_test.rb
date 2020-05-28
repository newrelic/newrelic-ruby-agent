# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require File.expand_path('../../../test_helper', __FILE__)

module NewRelic
  module Agent
    module InfiniteTracing
      class DataStoreSegmentIntegrationTest < Minitest::Test
        include FakeTraceObserverHelpers

        def test_sampled_segment_records_span_event
          trace_id      = nil
          txn_guid      = nil
          sampled       = nil
          priority      = nil
          timestamp     = nil
          sql_statement = "select * from table"

          span_events = generate_and_stream_segments do
  
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
          end

          assert_equal 2, span_events.size

          intrinsics        = span_events[0]['intrinsics']
          agent_attributes  = span_events[0]['agent_attributes']

          root_span_event   = span_events[1]
          root_guid         = root_span_event['intrinsics']['guid'].string_value

          datastore = 'Datastore/statement/SQLite/Blahg/select'

          assert_equal 'Span',      intrinsics['type'].string_value
          assert_equal trace_id,    intrinsics['traceId'].string_value
          refute                    intrinsics['guid'].string_value.empty?
          assert_equal root_guid,   intrinsics['parentId'].string_value
          assert_equal txn_guid,    intrinsics['transactionId'].string_value
          assert_equal sampled,     intrinsics['sampled'].bool_value
          assert_equal priority,    intrinsics['priority'].double_value
          assert_equal timestamp,   intrinsics['timestamp'].int_value
          assert_equal 1.0,         intrinsics['duration'].double_value
          assert_equal datastore,   intrinsics['name'].string_value
          assert_equal 'datastore', intrinsics['category'].string_value
          assert_equal 'SQLite',    intrinsics['component'].string_value
          assert_equal 'client',    intrinsics['span.kind'].string_value

          assert_equal 'calzone_zone',       agent_attributes['db.instance'].string_value
          assert_equal 'rachel.foo:1337807', agent_attributes['peer.address'].string_value
          assert_equal 'rachel.foo',         agent_attributes['peer.hostname'].string_value
          assert_equal sql_statement,        agent_attributes['db.statement'].string_value
        end

        def test_non_sampled_segment_does_record_span_event
          span_events = generate_and_stream_segments do
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
          end

          assert_equal 2, span_events.size
        end

      end
    end
  end
end
