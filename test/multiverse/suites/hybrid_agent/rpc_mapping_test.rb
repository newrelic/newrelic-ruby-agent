# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        class RpcMappingTest < Minitest::Test
          def setup
            # tracer would likely be:
            # opentelemetry-instrumentation-grpc
            # opentelemetry-instrumentation-gruf
            @tracer = NewRelic::Agent::OpenTelemetry::Trace::Tracer.new('OTelClient')
            harvest_transaction_events!
            harvest_span_events!
          end

          def teardown
            mocha_teardown
          end

          # The name and attributes for clients are based on gRPC client
          # instrumentation in the opentelmetry-instrumentation-grpc gem
          def client_span_name
            'support.proto.PingServer/RequestResponsePing'
          end

          def client_req_attrs
            {
              'rpc.system' => 'grpc',
              'rpc.service' => 'support.proto.PingServer',
              'rpc.method' => 'RequestResponsePing',
              'rpc.type' => 'request_response',
              'net.sock.peer.addr' => 'dns:///localhost:63752'
            }
          end

          # The name and attributes for servers are based on the gruf server
          # instrumentation in the opentelemetry-instrumentation-gruf gem
          def server_span_name
            '/proto.example.ExampleAPI/Example'
          end

          def server_req_attrs
            {
              'rpc.system' => 'grpc',
              'rpc.service' => 'proto.example.ExampleAPI',
              'rpc.method' => 'Example',
              'rpc.type' => 'request_response'
            }
          end

          # Using an array instead of a hash to mimic the instrumentation
          # which calls set_attribute. That method requires two args,
          # the key and the value. Both client and server instrumentation
          # attach this value the same way.
          def res_attrs
            ['rpc.grpc.status_code', 0]
          end

          def run_grpc_client_span
            in_transaction(category: :web) do |txn|
              txn.stubs(:sampled?).returns(true)

              @tracer.in_span(client_span_name, attributes: client_req_attrs, kind: :client) do |span|
                span.set_attribute(*res_attrs)
              end
            end
          end

          def run_grpc_server_span
            span = @tracer.start_span(server_span_name, attributes: server_req_attrs, kind: :server)
            span.finishable.stubs(:sampled?).returns(true)
            span.set_attribute(*res_attrs)
            span.finish
          end

          def test_client_segment_name
            run_grpc_client_span

            spans = harvest_span_events!
            span = spans[1][0]
            intrinsics = span[0]

            # This is the expected format in the spec
            # External/${host}/${rpc.service}/${rpc.method}
            # This means we intentionally set library to rpc.service in the start_external_request_segment
            # API call.
            assert_equal 'External/localhost/support.proto.PingServer/RequestResponsePing', intrinsics['name']
          end

          def test_client_transaction_metrics
            run_grpc_client_span

            assert_metrics_recorded([
              'External/allWeb',
              'External/localhost/support.proto.PingServer/RequestResponsePing',
              'WebTransactionTotalTime'
            ])
          end

          def test_client_span_intrinsic_attributes
            attrs = client_req_attrs
            run_grpc_client_span

            spans = harvest_span_events!
            span = spans[1][0]
            intrinsic = span[0]

            assert_equal attrs['rpc.service'], intrinsic['component']
            assert_equal attrs['rpc.method'], intrinsic['http.method']
            assert_equal attrs['rpc.method'], intrinsic['http.request.method']
            assert_equal 0, intrinsic['grpc.statusCode']
            assert_equal 'http', intrinsic['category']
            assert_equal 'client', intrinsic['span.kind']
            # we intentionally pull out the dns:// prefix, so the attr doesn't
            # match what was provided by the API call
            assert_equal 'localhost', intrinsic['server.address']
            assert_equal 63752, intrinsic['server.port']
          end

          def test_client_span_agent_attributes
            attrs = client_req_attrs
            run_grpc_client_span

            spans = harvest_span_events!
            span = spans[1][0]
            agent = span[2]

            assert_equal 'grpc://localhost:63752/support.proto.PingServer/RequestResponsePing', agent['http.url']
          end

          def test_client_span_custom_attributes
            attrs = client_req_attrs
            run_grpc_client_span

            spans = harvest_span_events!
            span = spans[1][0]
            custom = span[1]

            keys_assigned_elsewhere = %w[rpc.method net.sock.peer.addr rpc.status_code rpc.service]

            assert_empty custom.keys & keys_assigned_elsewhere
            assert_equal attrs['rpc.system'], custom['rpc.system']
            assert_equal attrs['rpc.type'], custom['rpc.type']
          end

          def test_server_transaction_name
            run_grpc_server_span

            txns = harvest_transaction_events!
            txn = txns[1][0]
            intrinsics = txn[0]

            assert_equal 'Controller/OTelClient/proto.example.ExampleAPI/Example', intrinsics['name']
          end

          def test_server_transaction_metrics
            run_grpc_server_span

            assert_metrics_recorded([
              'HttpDispatcher',
              'WebTransactionTotalTime',
              'Controller/OTelClient/proto.example.ExampleAPI/Example',
              'WebTransactionTotalTime/Controller/OTelClient/proto.example.ExampleAPI/Example'
            ])
          end

          def test_server_transaction_agent_attributes
            attrs = server_req_attrs
            run_grpc_server_span

            txns = harvest_transaction_events!
            txn = txns[1][0]
            agent = txn[2]

            assert_equal 0, agent[:'response.status']
            assert_equal attrs['rpc.method'], agent['request.method']
            assert_equal 'grpc://proto.example.ExampleAPI/Example', agent['request.uri']
          end

          def test_server_span_intrinsic_attributes
            attrs = server_req_attrs
            run_grpc_server_span

            spans = harvest_span_events!
            span = spans[1][0]
            intrinsic = span[0]

            assert_equal 'Controller/OTelClient/proto.example.ExampleAPI/Example', intrinsic['transaction.name']
          end

          def test_server_span_agent_attributes
            attrs = server_req_attrs
            run_grpc_server_span

            spans = harvest_span_events!
            span = spans[1][0]
            agent = span[2]

            assert_equal 0, agent[:'response.status']
          end

          def test_server_span_custom_attributes
            attrs = server_req_attrs
            run_grpc_server_span

            spans = harvest_span_events!
            span = spans[1][0]
            custom = span[1]

            keys_assigned_elsewhere = %w[rpc.method net.sock.peer.addr rpc.status_code]

            assert_empty custom.keys & keys_assigned_elsewhere
            assert_equal attrs['rpc.system'], custom['rpc.system']
            assert_equal attrs['rpc.type'], custom['rpc.type']
            assert_equal attrs['rpc.service'], custom['rpc.service']
          end

          def test_client_span_non_ok_status_code
            in_transaction(category: :web) do |txn|
              txn.stubs(:sampled?).returns(true)

              @tracer.in_span(client_span_name, attributes: client_req_attrs, kind: :client) do |span|
                span.set_attribute('rpc.grpc.status_code', 14)
              end
            end

            spans = harvest_span_events!
            span = spans[1][0]
            intrinsics = span[0]

            assert_equal 14, intrinsics['grpc.statusCode']
          end

          def test_server_span_non_ok_status_code
            span = @tracer.start_span(server_span_name, attributes: server_req_attrs, kind: :server)
            span.finishable.stubs(:sampled?).returns(true)
            span.set_attribute('rpc.grpc.status_code', 14)
            span.finish

            txns = harvest_transaction_events!
            txn = txns[1][0]
            agent = txn[2]

            assert_equal 14, agent[:'response.status']
          end
        end
      end
    end
  end
end
