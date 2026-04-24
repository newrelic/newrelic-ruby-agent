# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        # TODO: Run the tests to see how things get translated off the bat
        # TODO: Should the server and client RPC maps be checked in the same test?
        # TODO: Are other agents setting grpc.statusCode?
        class RpcMappingTest < Minitest::Test
          def setup
            @tracer = NewRelic::Agent::OpenTelemetry::Trace::Tracer.new('OTelClient')
            harvest_transaction_events!
            harvest_span_events!
          end

          def teardown
            mocha_teardown
          end

          # The name and attributes are based on gRPC client instrumentation
          # in the opentelmetry-instrumentation-grpc gem
          def span_name
            'support.proto.PingServer/RequestResponsePing'
          end

          # TODO: it looks like metadata headers can also be added in the grpc
          # otel instrumentation, but there are no examples in the tests

          # TODO: We don't get host in the gRPC instrumentation, but it's needed
          # to create the URI for external request segment...
          def req_attrs
            {
              'rpc.system' => 'grpc',
              'rpc.service' => 'support.proto.PingServer',
              'rpc.method' => 'RequestResponsePing',
              'rpc.type' => 'request_response',
              'net.sock.peer.addr' => '???' # TODO: - what do the otel spans spit out?
            }
          end

          # Using an array instead of a hash to mimic the instrumentation
          # which calls set_attribute. That method requires two args,
          # the key and the value.
          def res_attrs
            ['rpc.grpc.status_code', 0]
          end

          def run_grpc_client_segment
            in_transaction(category: :web) do |txn|
              txn.stubs(:sampled?).returns(true)

              @tracer.in_span(span_name, attributes: req_attrs, kind: :client) do |span|
                span.set_attribute(*res_attrs)
              end
            end
          end

          def test_segment_name
            run_grpc_client_segment

            spans = harvest_span_events!
            span = spans[1][0]
            intrinsics = span[0]

            # `External/${net.sock.peer.addr}/${rpc.service}/${rpc.method}`
            assert_equal "External/???/support.proto.PingServer/RequestResponsePing", intrinsics['name']
          end

          def test_transaction_metrics
            run_grpc_client_segment

            assert_metrics_recorded([
              'HttpDispatcher',
              'Controller/OTelClient/GET /sustainable-spuds',
              'WebTransactionTotalTime',
              'support.proto.PingServer/RequestResponsePing'
            ])
          end

          def test_transaction_agent_attributes
            attrs = req_attrs
            run_grpc_client_segment

            txns = harvest_transaction_events!
            txn = txns[1][0]
            agent = txn[2]

            expected_uri = 'grpc://???/service/method'

            assert_equal expected_uri, agent['request.uri']
            assert_equal attrs['server.address'], agent['request.headers.host']
            assert_equal attrs['server.port'], agent['request.headers.userAgent']
            assert_equal attrs['rpc.method'], agent['request.method']
            assert_equal 418, agent[:'http.statusCode'] # should we really be sending this as http.statusCode for RPC requests?
          end

          def test_span_custom_attributes
            attrs = req_attrs
            run_grpc_client_segment

            spans = harvest_span_events!
            span = spans[1][0]
            custom = span[1]

            keys_assigned_elsewhere = %w[rpc.method server.address rpc.status_code]

            assert_empty custom.keys & keys_assigned_elsewhere
            assert_equal attrs['rpc.service'], custom['rpc.service']
            assert_equal attrs['rpc.type'], custom['rpc.type']
            assert_equal attrs['net.sock.peer.address'], custom['net.sock.peer.addr']
          end
        end
      end
    end
  end
end
