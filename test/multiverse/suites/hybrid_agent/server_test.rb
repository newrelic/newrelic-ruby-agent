# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class ServerTest < Minitest::Test
      def setup
        @server_translator = NewRelic::Agent::OpenTelemetry::HttpServerTranslator
        harvest_transaction_events!
      end

      def teardown
        mocha_teardown
      end

      def test_create_server_transaction_name_with_stable_attributes
        original_name = 'GET'
        tracer_name = 'MyTracer'
        attributes = {
          'http.request.method' => 'GET',
          'url.path' => '/api/users'
        }

        result = @server_translator.create_server_transaction_name(original_name, tracer_name, attributes)

        assert_equal 'Controller/MyTracer/GET /api/users', result
      end

      def test_create_server_transaction_name_with_old_attributes
        original_name = 'HTTP GET'
        tracer_name = 'MyTracer'
        attributes = {
          'http.method' => 'POST',
          'http.target' => '/api/posts'
        }

        result = @server_translator.create_server_transaction_name(original_name, tracer_name, attributes)

        assert_equal 'Controller/MyTracer/POST /api/posts', result
      end

      def test_create_server_transaction_name_prefers_stable_attributes
        original_name = 'GET'
        tracer_name = 'MyTracer'
        attributes = {
          'http.request.method' => 'PUT',
          'http.method' => 'GET',
          'url.path' => '/stable/path',
          'http.target' => '/old/path'
        }

        result = @server_translator.create_server_transaction_name(original_name, tracer_name, attributes)

        assert_equal 'Controller/MyTracer/PUT /stable/path', result
      end

      def test_create_server_transaction_name_returns_original_when_method_missing
        original_name = 'GET'
        tracer_name = 'MyTracer'
        attributes = {
          'server.address' => 'example.com',
          'url.path' => '/api/users'
        }

        result = @server_translator.create_server_transaction_name(original_name, tracer_name, attributes)

        assert_equal original_name, result
      end

      def test_create_server_transaction_name_returns_original_when_path_missing
        original_name = 'GET'
        tracer_name = 'MyTracer'
        attributes = {
          'http.request.method' => 'GET'
        }

        result = @server_translator.create_server_transaction_name(original_name, tracer_name, attributes)

        assert_equal original_name, result
      end

      def test_create_server_transaction_name_returns_original_when_all_missing
        original_name = 'HTTP GET'
        tracer_name = 'MyTracer'
        attributes = {}

        result = @server_translator.create_server_transaction_name(original_name, tracer_name, attributes)

        assert_equal original_name, result
      end

      def test_create_server_transaction_name_with_nil_attributes
        original_name = 'GET'
        tracer_name = 'MyTracer'

        result = @server_translator.create_server_transaction_name(original_name, tracer_name, nil)

        assert_equal original_name, result
      end
    end
  end
end
