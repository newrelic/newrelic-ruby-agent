# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'base_translator'

module NewRelic
  module Agent
    module OpenTelemetry
      class RpcTranslator < BaseTranslator
        def mappings_hash
          RPC_MAPPINGS
        end

        def extra_operations(result: {}, name: nil, attributes: nil, instrumentation_scope: nil)
          uri = build_uri(attributes)
          result[:for_segment_api][:uri] = uri if uri

          result
        end

        def build_uri(attributes)
          host = attributes['server.address'] || attributes['net.peer.name'] || attributes['net.sock.peer.addr']
          service = attributes['rpc.service']
          method = attributes['rpc.method']
          return unless host && method

          if host && service && method
            "grpc://#{host}/#{service}/#{method}"
          else
            "grpc://#{host}/#{method}"
          end
        end
      end
    end
  end
end
