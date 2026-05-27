# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'base_translator'

module NewRelic
  module Agent
    module OpenTelemetry
      class RpcTranslator < BaseTranslator
        class << self
          def mappings_hash(kind)
            kind == :client ? AttributeMappings::RPC_CLIENT_MAPPINGS : AttributeMappings::RPC_SERVER_MAPPINGS
          end

          def add_specialized_attributes(result: {}, name: nil, attributes: nil, instrumentation_scope: nil, kind: nil)
            case kind
            when :client
              uri = build_uri(attributes)
              result[:for_segment_api][:uri] = uri if uri
            when :server
              server_name = create_server_transaction_name(name: name, attributes: attributes, instrumentation_scope: instrumentation_scope) if name
              result[:for_segment_api][:name] = server_name if server_name

              uri = build_uri(attributes)
              if uri
                result[:agent]['request.uri'] = {value: uri, destinations: AttributeMappings::DEFAULT_DESTINATIONS}
              end
            end

            result
          end

          def create_server_transaction_name(name: nil, attributes: nil, instrumentation_scope: nil)
            txn_name = name&.delete_prefix(NewRelic::SLASH)
            Instrumentation::ControllerInstrumentation::TransactionNamer.name_for(nil, nil, :web, {class_name: instrumentation_scope, name: txn_name})
          end

          def build_uri(attributes)
            host = attributes['server.address'] || attributes['net.peer.name'] || attributes['net.sock.peer.addr']
            # in otel contrib's grpc instrumentation, the test example starts
            # with "dns:///", which can't be accurately parsed using ::URI.parse
            host = host&.delete_prefix('dns:///')
            service = attributes['rpc.service']
            method = attributes['rpc.method']

            if host && service && method
              "grpc://#{host}/#{service}/#{method}"
            elsif host && method
              "grpc://#{host}/#{method}"
            elsif service && method
              "grpc://#{service}/#{method}"
            end
          end
        end
      end
    end
  end
end
