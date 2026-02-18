# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        class DbMappingTest < Minitest::Test
          def setup
            @tracer = NewRelic::Agent::OpenTelemetry::Trace::Tracer.new('OTelClient')
            harvest_span_events!
            harvest_transaction_events!
          end

          def teardown
            mocha_teardown
          end

          def db_attrs
            {
              'db.system' => 'trilogy',
              'db.statement' => 'SELECT * FROM users WHERE users.id = 1 and users.email = "test@test.com"',
              'db.name' => 'customers',
              'db.user' => 'user',
              'peer.service' => 'readonly:mysql',
              'db.instance.id' => '123456',
              'net.peer.name' => 'example.host',
              'net.peer.port' => '3306'
            }
          end

          def start_db_client_segment
            in_transaction(category: :web) do |txn|
              txn.stubs(:sampled?).returns(true)

              @tracer.in_span('select', attributes: db_attrs.dup, kind: :client) do |span|
                # noop
              end
            end
          end

          def test_db_system_segment_v_1_17_segment_properties
            transaction = start_db_client_segment

            segment = transaction.segments[1]

            assert_instance_of NewRelic::Agent::Transaction::DatastoreSegment, segment

            assert_equal 'Datastore/operation/trilogy/select', segment.name
            assert_equal db_attrs['net.peer.name'], segment.host
          end

          def test_db_system_segment_v_1_17_metrics
            start_db_client_segment

            assert_metrics_recorded([
              'Datastore/all',
              'Datastore/allWeb',
              'Datastore/instance/trilogy/example.host/3306',
              'Datastore/operation/trilogy/select',
              'Datastore/trilogy/all'
            ])
          end

          def test_db_system_segment_v_1_17_intrinsic_attributes
            start_db_client_segment

            spans = harvest_span_events!
            span = spans[1][0]
            intrinsics = span[0]

            assert_equal db_attrs['db.system'], intrinsics['component']
            assert_equal 'client', intrinsics['span.kind']
            assert_equal 'datastore', intrinsics['category']
          end

          def test_db_system_segment_v_1_17_agent_attributes
            start_db_client_segment

            spans = harvest_span_events!
            span = spans[1][0]
            agent = span[2]

            assert_equal db_attrs['db.name'], agent['db.instance']
            assert_equal "#{db_attrs['net.peer.name']}:#{db_attrs['net.peer.port']}", agent['peer.address']
            assert_equal db_attrs['net.peer.name'], agent['peer.hostname']
            assert_equal db_attrs['net.peer.name'], agent['server.address']
            assert_equal db_attrs['net.peer.port'], agent['server.port']
            assert_equal db_attrs['db.system'], agent['db.system']
            # statement is obfuscated by the _notice_sql call
            assert_equal 'SELECT * FROM users WHERE users.id = ? and users.email = ?', agent['db.statement']
          end

          # TODO: The only custom attributes that should be attached
          # are values that aren't present in the other attribute categories.
          # All attributes are represented here so that a test fails when the
          # change is made.
          # Expected custom attributes to remain are:
          # db.name, db.user, peer.service, db.instance.id
          def test_db_system_segment_v_1_17_custom_attributes
            start_db_client_segment

            spans = harvest_span_events!
            span = spans[1][0]
            custom = span[1]

            assert_equal db_attrs['db.system'], custom['db.system']
            assert_equal db_attrs['db.statement'], custom['db.statement']
            assert_equal db_attrs['db.name'], custom['db.name']
            assert_equal db_attrs['db.user'], custom['db.user']
            assert_equal db_attrs['peer.service'], custom['peer.service']
            assert_equal db_attrs['db.instance.id'], custom['db.instance.id']
            assert_equal db_attrs['net.peer.name'], custom['net.peer.name']
            assert_equal db_attrs['net.peer.port'], custom['net.peer.port']
          end
        end
      end
    end
  end
end
