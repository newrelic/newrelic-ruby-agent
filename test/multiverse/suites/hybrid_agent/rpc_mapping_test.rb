# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        # This class only tests gRPC client instrumentation.
        # OpenTelemetry Ruby does not have gRPC instrumentation for server calls.
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

          def req_attrs
            {
              'rpc.system' => 'grpc',
              'rpc.service' => 'support.proto.PingServer',
              'rpc.method' => 'RequestResponsePing',
              'rpc.type' => 'request_response',
              'net.sock.peer.addr' => 'dns:///localhost:63752'
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

            # This is the expected format in the spec
            # External/${host}/${rpc.service}/${rpc.method}
            # This means we intentionally set library to rpc.service in the start_external_request_segment
            # API call.
            assert_equal 'External/localhost/support.proto.PingServer/RequestResponsePing', intrinsics['name']
          end

          def test_transaction_metrics
            run_grpc_client_segment

            assert_metrics_recorded([
              'External/allWeb',
              'External/localhost/support.proto.PingServer/RequestResponsePing',
              'WebTransactionTotalTime'
            ])
          end

          def test_span_intrinsic_attributes
            attrs = req_attrs
            run_grpc_client_segment

            spans = harvest_span_events!
            span = spans[1][0]
            intrinsic = span[0]

            assert_equal attrs['rpc.service'], intrinsic['component']
            assert_equal attrs['rpc.method'], intrinsic['http.method']
            assert_equal attrs['rpc.method'], intrinsic['http.request.method']
            assert_equal 0, intrinsic['http.statusCode']
            assert_equal 'http', intrinsic['category']
            assert_equal 'client', intrinsic['span.kind']
            # we intentionally pull out the dns:// prefix, so the attr doesn't
            # match what was provided by the API call
            assert_equal 'localhost', intrinsic['server.address']
            assert_equal 63752, intrinsic['server.port']
          end

          def test_span_agent_attributes
            attrs = req_attrs
            run_grpc_client_segment

            spans = harvest_span_events!
            span = spans[1][0]
            agent = span[2]

            assert_equal 'grpc://localhost:63752/support.proto.PingServer/RequestResponsePing', agent['http.url']
          end

          def test_span_custom_attributes
            attrs = req_attrs
            run_grpc_client_segment

            spans = harvest_span_events!
            span = spans[1][0]
            custom = span[1]

            keys_assigned_elsewhere = %w[rpc.method net.sock.peer.addr rpc.status_code rpc.service]

            assert_empty custom.keys & keys_assigned_elsewhere
            assert_equal attrs['rpc.system'], custom['rpc.system']
            assert_equal attrs['rpc.type'], custom['rpc.type']
          end
        end
      end
    end
  end
end
