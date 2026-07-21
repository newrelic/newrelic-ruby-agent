# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/continuous_profiling/otlp_exporter'

module NewRelic::Agent::ContinuousProfiling
  class OtlpExporterTest < Minitest::Test
    ENDPOINT_CONFIG = {
      :'continuous_profiler.otlp_endpoint.host' => 'otlp.example.com',
      :'continuous_profiler.otlp_endpoint.port' => 4318,
      :'continuous_profiler.otlp_endpoint.path' => '/v1/profiles'
    }.freeze

    def setup
      @exporter = OtlpExporter.new
      @response = stub_everything('response')
      @connection = stub_everything('http connection', :request => @response)
      Net::HTTP.stubs(:new).returns(@connection)
    end

    def test_export_posts_gzip_compressed_protobuf_to_the_configured_endpoint
      with_config(ENDPOINT_CONFIG) do
        request = nil
        @connection.stubs(:request).with { |req| request = req; true }.returns(@response)

        @exporter.export('raw-bytes')

        assert_equal 'application/x-protobuf', request['Content-Type']
        assert_equal 'gzip', request['Content-Encoding']
        assert_equal 'raw-bytes', Zlib.gunzip(request.body)
        assert_equal '/v1/profiles', request.path
      end
    end

    def test_export_sends_the_license_key_as_the_api_key_header
      with_config(ENDPOINT_CONFIG.merge(:license_key => 'abc123')) do
        request = nil
        @connection.stubs(:request).with { |req| request = req; true }.returns(@response)

        @exporter.export('raw-bytes')

        assert_equal 'abc123', request['api-key']
      end
    end

    def test_export_uses_a_plain_connection_without_a_configured_proxy
      with_config(ENDPOINT_CONFIG) do
        Net::HTTP.expects(:new).with('otlp.example.com', 4318).returns(@connection)

        @exporter.export('raw-bytes')
      end
    end

    def test_export_routes_through_the_configured_proxy
      proxy_class = Class.new(Net::HTTP)
      Net::HTTP.expects(:Proxy).with('proxy.example.com', 8080, 'user', 'pass').returns(proxy_class)
      proxy_class.expects(:new).with('otlp.example.com', 4318).returns(@connection)

      with_config(ENDPOINT_CONFIG.merge(
        :proxy_host => 'proxy.example.com',
        :proxy_port => 8080,
        :proxy_user => 'user',
        :proxy_pass => 'pass'
      )) do
        @exporter.export('raw-bytes')
      end
    end

    def test_export_records_data_usage_and_duration_supportability_metrics
      with_config(ENDPOINT_CONFIG) do
        @exporter.export('raw-bytes')

        assert_metrics_recorded(['Supportability/Ruby/OTLP/Profiles/Output/Bytes', 'Supportability/Ruby/Profiling/Export/Duration'])
      end
    end

    def test_export_rescues_connection_failures_and_records_a_failure_metric
      @connection.stubs(:request).raises(Errno::ECONNREFUSED)

      with_config(ENDPOINT_CONFIG) do
        result = @exporter.export('raw-bytes')

        assert_nil result
        assert_metrics_recorded('Supportability/Ruby/Profiling/Export/Failure')
      end
    end
  end
end
