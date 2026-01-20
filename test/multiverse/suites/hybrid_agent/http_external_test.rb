# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class HttpExternalTest < Minitest::Test
      class TestClass
        include NewRelic::Agent::OpenTelemetry::Segments::HttpExternal
      end

      def setup
        @test_instance = TestClass.new
      end

      def test_create_uri_with_all_components_v_1_23
        attributes = {
          'url.scheme' => 'https',
          'server.address' => 'example.com',
          'server.port' => 443,
          'url.path' => '/api/v1/users'
        }

        result = @test_instance.create_uri(attributes)

        assert_equal 'https://example.com:443/api/v1/users', result
      end

      def test_create_uri_with_all_components_v_1_17
        attributes = {
          'http.scheme' => 'http',
          'net.peer.name' => 'api.example.com',
          'net.peer.port' => 8080,
          'http.target' => '/search?q=test'
        }

        result = @test_instance.create_uri(attributes)

        assert_equal 'http://api.example.com:8080/search?q=test', result
      end

      def test_create_uri_defaults_to_root_path
        attributes = {
          'url.scheme' => 'https',
          'server.address' => 'example.com',
          'server.port' => 443
        }

        result = @test_instance.create_uri(attributes)

        assert_equal 'https://example.com:443/', result
      end

      def test_create_uri_falls_back_to_url_full_when_scheme_missing
        attributes = {
          'server.address' => 'example.com',
          'server.port' => 443,
          'url.path' => '/api',
          'url.full' => 'https://example.com/api'
        }

        result = @test_instance.create_uri(attributes)

        assert_equal 'https://example.com/api', result
      end

      def test_create_uri_falls_back_to_http_url_when_host_missing
        attributes = {
          'url.scheme' => 'https',
          'server.port' => 443,
          'url.path' => '/api',
          'http.url' => 'https://fallback.com/api'
        }

        result = @test_instance.create_uri(attributes)

        assert_equal 'https://fallback.com/api', result
      end

      def test_create_uri_falls_back_when_port_missing
        attributes = {
          'url.scheme' => 'https',
          'server.address' => 'example.com',
          'url.path' => '/api',
          'url.full' => 'https://example.com/api'
        }

        result = @test_instance.create_uri(attributes)

        assert_equal 'https://example.com/api', result
      end

      def test_create_uri_prefers_url_scheme_over_http_scheme
        attributes = {
          'url.scheme' => 'https',
          'http.scheme' => 'http',
          'server.address' => 'example.com',
          'server.port' => 443,
          'url.path' => '/api'
        }

        result = @test_instance.create_uri(attributes)

        assert_equal 'https://example.com:443/api', result
      end

      def test_create_uri_prefers_server_address_over_net_peer_name
        attributes = {
          'url.scheme' => 'https',
          'server.address' => 'primary.com',
          'net.peer.name' => 'secondary.com',
          'server.port' => 443,
          'url.path' => '/api'
        }

        result = @test_instance.create_uri(attributes)

        assert_equal 'https://primary.com:443/api', result
      end

      def test_create_uri_prefers_server_port_over_net_peer_port
        attributes = {
          'url.scheme' => 'https',
          'server.address' => 'example.com',
          'server.port' => 8443,
          'net.peer.port' => 443,
          'url.path' => '/api'
        }

        result = @test_instance.create_uri(attributes)

        assert_equal 'https://example.com:8443/api', result
      end

      def test_create_uri_prefers_url_path_over_http_target
        attributes = {
          'url.scheme' => 'https',
          'server.address' => 'example.com',
          'server.port' => 443,
          'url.path' => '/v2/api',
          'http.target' => '/v1/api'
        }

        result = @test_instance.create_uri(attributes)

        assert_equal 'https://example.com:443/v2/api', result
      end

      def test_create_uri_prefers_url_full_over_http_url
        attributes = {
          'url.full' => 'https://primary.com/api',
          'http.url' => 'https://secondary.com/api'
        }

        result = @test_instance.create_uri(attributes)

        assert_equal 'https://primary.com/api', result
      end

      def test_create_uri_returns_nil_when_no_attributes
        attributes = {}

        result = @test_instance.create_uri(attributes)

        assert_nil result
      end
    end
  end
end
