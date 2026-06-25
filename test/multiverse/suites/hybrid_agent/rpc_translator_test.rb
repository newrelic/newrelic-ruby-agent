# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      class RpcTranslatorTest < Minitest::Test
        def translator
          RpcTranslator
        end

        def test_mappings_hash_returns_client_mappings_for_client_kind
          assert_same AttributeMappings::RPC_CLIENT_MAPPINGS, translator.mappings_hash(:client)
        end

        def test_mappings_hash_returns_server_mappings_for_server_kind
          assert_same AttributeMappings::RPC_SERVER_MAPPINGS, translator.mappings_hash(:server)
        end

        def test_build_uri_with_host_service_and_method
          attrs = {
            'server.address' => 'myhost.example.com',
            'rpc.service' => 'MyService',
            'rpc.method' => 'DoThing'
          }

          assert_equal 'grpc://myhost.example.com/MyService/DoThing', translator.build_uri(attrs)
        end

        def test_build_uri_with_host_and_method_only
          attrs = {'server.address' => 'myhost.example.com', 'rpc.method' => 'DoThing'}

          assert_equal 'grpc://myhost.example.com/DoThing', translator.build_uri(attrs)
        end

        def test_build_uri_with_service_and_method_only
          attrs = {'rpc.service' => 'MyService', 'rpc.method' => 'DoThing'}

          assert_equal 'grpc://MyService/DoThing', translator.build_uri(attrs)
        end

        def test_build_uri_returns_nil_when_no_relevant_attributes
          assert_nil translator.build_uri({})
        end

        def test_build_uri_returns_nil_with_only_rpc_system
          assert_nil translator.build_uri({'rpc.system' => 'grpc'})
        end

        def test_build_uri_strips_dns_scheme_prefix
          attrs = {
            'server.address' => 'dns:///localhost:50051',
            'rpc.service' => 'MyService',
            'rpc.method' => 'DoThing'
          }

          assert_equal 'grpc://localhost:50051/MyService/DoThing', translator.build_uri(attrs)
        end

        def test_build_uri_strips_xds_scheme_prefix
          attrs = {
            'server.address' => 'xds:///my-cluster',
            'rpc.service' => 'MyService',
            'rpc.method' => 'DoThing'
          }

          assert_equal 'grpc://my-cluster/MyService/DoThing', translator.build_uri(attrs)
        end

        def test_build_uri_leaves_plain_host_unchanged
          attrs = {
            'server.address' => 'localhost:50051',
            'rpc.service' => 'MyService',
            'rpc.method' => 'DoThing'
          }

          assert_equal 'grpc://localhost:50051/MyService/DoThing', translator.build_uri(attrs)
        end

        def test_build_uri_prefers_server_address_over_net_sock_peer_addr
          attrs = {
            'server.address' => 'preferred.example.com',
            'net.sock.peer.addr' => 'fallback.example.com',
            'rpc.service' => 'MyService',
            'rpc.method' => 'DoThing'
          }

          assert_equal 'grpc://preferred.example.com/MyService/DoThing', translator.build_uri(attrs)
        end

        def test_build_uri_falls_back_to_net_peer_name
          attrs = {
            'net.peer.name' => 'legacy.example.com',
            'rpc.service' => 'MyService',
            'rpc.method' => 'DoThing'
          }

          assert_equal 'grpc://legacy.example.com/MyService/DoThing', translator.build_uri(attrs)
        end

        def test_build_uri_falls_back_to_net_sock_peer_addr
          attrs = {
            'net.sock.peer.addr' => 'sockaddr.example.com',
            'rpc.service' => 'MyService',
            'rpc.method' => 'DoThing'
          }

          assert_equal 'grpc://sockaddr.example.com/MyService/DoThing', translator.build_uri(attrs)
        end

        def test_create_server_transaction_name_strips_leading_slash
          name = translator.create_server_transaction_name(
            name: '/proto.example.Service/Method',
            instrumentation_scope: 'OTelTracer'
          )

          assert_equal 'Controller/OTelTracer/proto.example.Service/Method', name
        end

        def test_create_server_transaction_name_without_leading_slash
          name = translator.create_server_transaction_name(
            name: 'proto.example.Service/Method',
            instrumentation_scope: 'OTelTracer'
          )

          assert_equal 'Controller/OTelTracer/proto.example.Service/Method', name
        end

        def test_translate_client_routes_status_code_to_instance_variable
          attrs = {'rpc.grpc.status_code' => 0}
          result = translator.translate(attributes: attrs, kind: :client)

          assert_equal 0, result[:instance_variable]['grpc_status_code']
        end

        def test_translate_client_routes_service_to_segment_api_library
          attrs = {'rpc.service' => 'proto.example.MyService'}
          result = translator.translate(attributes: attrs, kind: :client)

          assert_equal 'proto.example.MyService', result[:for_segment_api][:library]
        end

        def test_translate_client_routes_method_to_segment_api_procedure
          attrs = {'rpc.method' => 'DoThing'}
          result = translator.translate(attributes: attrs, kind: :client)

          assert_equal 'DoThing', result[:for_segment_api][:procedure]
        end

        def test_translate_client_routes_host_to_segment_api_host
          attrs = {'net.sock.peer.addr' => 'dns:///localhost:50051'}
          result = translator.translate(attributes: attrs, kind: :client)

          assert_equal 'dns:///localhost:50051', result[:for_segment_api][:host]
        end

        def test_translate_client_builds_uri_in_segment_api
          attrs = {
            'server.address' => 'localhost:50051',
            'rpc.service' => 'MyService',
            'rpc.method' => 'DoThing'
          }
          result = translator.translate(attributes: attrs, kind: :client)

          assert_equal 'grpc://localhost:50051/MyService/DoThing', result[:for_segment_api][:uri]
        end

        def test_translate_client_puts_unrecognized_attrs_in_custom
          attrs = {'rpc.system' => 'grpc', 'rpc.type' => 'request_response'}
          result = translator.translate(attributes: attrs, kind: :client)

          assert_equal 'grpc', result[:custom]['rpc.system']
          assert_equal 'request_response', result[:custom]['rpc.type']
        end

        def test_translate_server_routes_status_code_to_instance_variable
          attrs = {'rpc.grpc.status_code' => 14}
          result = translator.translate(attributes: attrs, kind: :server)

          assert_equal 14, result[:instance_variable]['response_status']
        end

        def test_translate_server_routes_request_method_to_agent_attributes
          attrs = {'rpc.method' => 'DoThing'}
          result = translator.translate(attributes: attrs, kind: :server)

          assert_equal 'DoThing', result[:agent]['request.method'][:value]
        end

        def test_translate_server_builds_uri_as_agent_attribute
          attrs = {'rpc.service' => 'proto.example.Service', 'rpc.method' => 'Method'}
          result = translator.translate(attributes: attrs, kind: :server)

          assert_equal 'grpc://proto.example.Service/Method', result[:agent]['request.uri'][:value]
        end

        def test_translate_server_sets_transaction_name_in_segment_api
          attrs = {'rpc.service' => 'proto.example.Service', 'rpc.method' => 'Method'}
          result = translator.translate(
            attributes: attrs,
            name: '/proto.example.Service/Method',
            instrumentation_scope: 'OTelTracer',
            kind: :server
          )

          assert_equal 'Controller/OTelTracer/proto.example.Service/Method', result[:for_segment_api][:name]
        end

        def test_translate_server_puts_unrecognized_attrs_in_custom
          attrs = {'rpc.system' => 'grpc', 'rpc.type' => 'request_response'}
          result = translator.translate(attributes: attrs, kind: :server)

          assert_equal 'grpc', result[:custom]['rpc.system']
          assert_equal 'request_response', result[:custom]['rpc.type']
        end
      end
    end
  end
end
