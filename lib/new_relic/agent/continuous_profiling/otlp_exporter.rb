# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'net/http'
require 'zlib'
require_relative 'otlp_endpoint'

module NewRelic
  module Agent
    module ContinuousProfiling
      # Sends an already-encoded OTLP profile payload to the (placeholder, see
      # OtlpEndpoint) destination over HTTP. Deliberately independent of NewRelicService,
      # which is built around the RPM collector's own auth/connect protocol -- none of
      # which applies to an OTLP export's header-based auth and raw protobuf body.
      #
      # No retry queue: a failed export is logged and dropped. The next harvest tick
      # tries again with fresh data.
      class OtlpExporter
        CONTENT_TYPE = 'application/x-protobuf'
        CONTENT_ENCODING = 'gzip'
        BYTES_METRIC = 'Supportability/Ruby/OTLP/Profiles/Output/Bytes'
        DURATION_METRIC = 'Supportability/Ruby/Profiling/Export/Duration'
        FAILURE_METRIC = 'Supportability/Ruby/Profiling/Export/Failure'

        def export(profile_bytes)
          uri = OtlpEndpoint.uri
          body = Zlib.gzip(profile_bytes)
          request = build_request(uri, body)

          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          response = http_connection(uri).request(request)
          record_metrics(body.bytesize, Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time)
          log_response(response)
          response
        rescue => e
          NewRelic::Agent.logger.debug("Failed to export continuous profiling data: #{e.class}: #{e.message}")
          NewRelic::Agent.increment_metric(FAILURE_METRIC)
          nil
        end

        private

        # Mirrors NewRelicService#log_response, for debug-log visibility into export acceptance.
        def log_response(response)
          NewRelic::Agent.logger.debug(
            "Received continuous profiling export response, status: #{response.code} #{response.message}, " \
            "body: #{response.body}"
          )
        end

        def build_request(uri, body)
          request = Net::HTTP::Post.new(uri.request_uri)
          request['Content-Type'] = CONTENT_TYPE
          request['Content-Encoding'] = CONTENT_ENCODING
          request['api-key'] = NewRelic::Agent.config[:license_key]
          request.body = body
          request
        end

        def http_connection(uri)
          conn = build_connection(uri)
          conn.use_ssl = uri.scheme == 'https'
          timeout = NewRelic::Agent.config[:timeout]
          conn.open_timeout = timeout
          conn.read_timeout = timeout
          conn.write_timeout = timeout
          conn
        end

        def build_connection(uri)
          return Net::HTTP.new(uri.host, uri.port) unless NewRelic::Agent.config[:proxy_host]

          Net::HTTP::Proxy(
            NewRelic::Agent.config[:proxy_host],
            NewRelic::Agent.config[:proxy_port],
            NewRelic::Agent.config[:proxy_user],
            NewRelic::Agent.config[:proxy_pass]
          ).new(uri.host, uri.port)
        end

        def record_metrics(bytesize, duration)
          NewRelic::Agent.record_metric(DURATION_METRIC, duration)
          NewRelic::Agent.record_metric(BYTES_METRIC, bytesize)
        end
      end
    end
  end
end
