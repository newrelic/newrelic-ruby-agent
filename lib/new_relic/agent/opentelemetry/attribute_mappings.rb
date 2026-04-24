# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module AttributeMappings
        DEFAULT_DESTINATIONS = AttributeFilter::DST_TRANSACTION_TRACER |
          AttributeFilter::DST_TRANSACTION_EVENTS |
          AttributeFilter::DST_ERROR_COLLECTOR

        # The AttributeMappings module includes constants with the way otel_keys
        # map to New Relic attributes.
        #
        # The topmost key should be the New Relic attribute, argument, or
        # instance variable to translate as a string.
        #
        # The value for that key is a hash.
        # The permitted keys in that hash are:
        # * :otel_keys (required) an array of strings with the semantic conventions to translate
        # * :category (optional) a symbol of the category to apply this attribute
        # available categories are :intrinsic, :agent, and :instance_variable
        # * :segment_field (optional) the name of an argument used in a segment
        # API that is equal to this otel key
        # * destinations (optional) If the category is :agent, then the destinations
        # field must be defined. This is a bitwise value crafted from the
        # AttributeFilter constants for various destinations, ex.
        # AttributeFilter::DST_TRANSACTION_TRACER to apply the agent attribute
        # on transaction traces.
        #
        # You can list known semantic conventions we are mapping to in a comment
        # on the constant.

        HTTP_CLIENT_MAPPINGS = { # v1.23, v1.17
          'http_status_code' => {
            otel_keys: ['http.response.status_code', 'http.status_code'],
            category: :instance_variable
          },
          'procedure' => {
            otel_keys: ['http.request.method', 'http.method'],
            segment_field: :procedure
          },
          'http.url' => {
            otel_keys: ['url.full', 'http.url'],
            segment_field: :uri
          },
          'host' => {
            otel_keys: ['server.address', 'net.peer.name'],
            category: :intrinsic
          },
          'port' => {
            otel_keys: ['server.port', 'net.peer.port'],
            category: :intrinsic
          }
        }.freeze

        DATASTORE_MAPPINGS = { # v1.25, v1.17
          'product' => {
            otel_keys: ['db.system.name', 'db.system'],
            segment_field: :product
          },
          'database_name' => {
            otel_keys: ['db.namespace', 'db.name'],
            segment_field: :database_name
          },
          'host' => {
            otel_keys: ['server.address', 'net.peer.name'],
            segment_field: :host
          },
          'port_path_or_id' => {
            otel_keys: ['server.port', 'net.peer.port'],
            segment_field: :port_path_or_id
          },
          'collection' => {
            otel_keys: ['db.collection.name', 'db.sql.table'],
            segment_field: :collection
          },
          'operation' => {
            otel_keys: ['db.operation.name', 'db.operation'],
            segment_field: :operation
          },
          'sql' => {
            otel_keys: ['db.statement', 'db.query.text'],
            segment_field: :sql
          }
        }.freeze

        HTTP_SERVER_MAPPINGS = { # v1.23, v1.20
          'http_response_code' => {
            otel_keys: ['http.response.status_code', 'http.status_code'],
            category: :instance_variable
          },
          'request.uri' => {
            otel_keys: ['http.target', 'url.path'],
            category: :agent,
            destinations: DEFAULT_DESTINATIONS
          },
          'request.headers.host' => {
            otel_keys: ['server.address', 'http.host'],
            category: :agent,
            destinations: DEFAULT_DESTINATIONS
          },
          'request.headers.userAgent' => {
            otel_keys: ['user_agent.original', 'http.user_agent'],
            category: :agent,
            destinations: DEFAULT_DESTINATIONS
          },
          'request.method' => {
            otel_keys: ['http.request.method', 'http.method'],
            category: :agent,
            destinations: DEFAULT_DESTINATIONS
          }
        }.freeze

        # use start_external_request_segment API for client
        RPC_MAPPINGS = { # v1.23, v1.17 client, v1.20 server
          # not currently captured by NR
          'grpc.statusCode' => {
            otel_keys: ['rpc.grpc.status_code'],
            instance_variable: :http_status_code
            # tbd
          },
          'library' => {
            otel_keys: ['rpc.system'],
            segment_field: :library
          },
          'procedure' => {
            otel_keys: ['rpc.method'],
            segment_field: :procedure
          },
          'host' => {
            # traditional host keys aren't sent by otel grpc instrumentation
            # so we use net.sock.peer.address to fill the host field
            otel_keys: ['net.sock.peer.addr', 'server.address', 'net.peer.name'],
            segment_field: :host
          },
          'port' => { # not sent by gRPC OTel instrumentation
            otel_keys: ['server.port', 'net.peer.port'],
            segment_field: :port
          }
        }.freeze
      end
    end
  end
end
