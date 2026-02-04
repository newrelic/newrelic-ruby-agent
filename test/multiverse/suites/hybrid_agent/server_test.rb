# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class ServerTest < Minitest::Test
      class TestClass
        include NewRelic::Agent::OpenTelemetry::Segments::Server
      end

      def setup
        @test_instance = TestClass.new
      end

      def test_set_server_transaction_name_with_stable_attributes
        original_name = 'GET'
        tracer_name = 'MyTracer'
        attributes = {
          'server.address' => 'example.com',
          'http.request.method' => 'GET',
          'url.path' => '/api/users'
        }

        result = @test_instance.set_server_transaction_name(original_name, tracer_name, attributes)

        assert_equal 'Controller/MyTracer/example.com/GET /api/users', result
      end

      def test_set_server_transaction_name_with_old_attributes
        original_name = 'HTTP GET'
        tracer_name = 'MyTracer'
        attributes = {
          'http.host' => 'example.com',
          'http.method' => 'POST',
          'http.target' => '/api/posts'
        }

        result = @test_instance.set_server_transaction_name(original_name, tracer_name, attributes)

        assert_equal 'Controller/MyTracer/example.com/POST /api/posts', result
      end

      def test_set_server_transaction_name_prefers_stable_attributes
        original_name = 'GET'
        tracer_name = 'MyTracer'
        # Mix of stable and old attributes - stable should be preferred
        attributes = {
          'server.address' => 'stable.example.com',
          'http.host' => 'old.example.com',
          'http.request.method' => 'PUT',
          'http.method' => 'GET',
          'url.path' => '/stable/path',
          'http.target' => '/old/path'
        }

        result = @test_instance.set_server_transaction_name(original_name, tracer_name, attributes)

        assert_equal 'Controller/MyTracer/stable.example.com/PUT /stable/path', result
      end

      def test_set_server_transaction_name_returns_original_when_host_missing
        original_name = 'GET'
        tracer_name = 'MyTracer'
        attributes = {
          'http.request.method' => 'GET',
          'url.path' => '/api/users'
        }

        result = @test_instance.set_server_transaction_name(original_name, tracer_name, attributes)

        assert_equal original_name, result
      end

      def test_set_server_transaction_name_returns_original_when_method_missing
        original_name = 'GET'
        tracer_name = 'MyTracer'
        attributes = {
          'server.address' => 'example.com',
          'url.path' => '/api/users'
        }

        result = @test_instance.set_server_transaction_name(original_name, tracer_name, attributes)

        assert_equal original_name, result
      end

      def test_set_server_transaction_name_returns_original_when_path_missing
        original_name = 'GET'
        tracer_name = 'MyTracer'
        attributes = {
          'server.address' => 'example.com',
          'http.request.method' => 'GET'
        }

        result = @test_instance.set_server_transaction_name(original_name, tracer_name, attributes)

        assert_equal original_name, result
      end

      def test_set_server_transaction_name_returns_original_when_all_missing
        original_name = 'GET'
        tracer_name = 'MyTracer'
        attributes = {}

        result = @test_instance.set_server_transaction_name(original_name, tracer_name, attributes)

        assert_equal original_name, result
      end

      def test_set_server_transaction_name_with_nil_attributes
        original_name = 'GET'
        tracer_name = 'MyTracer'

        result = @test_instance.set_server_transaction_name(original_name, tracer_name, nil)

        assert_equal original_name, result
      end

      # update_request_attributes tests

      def test_update_request_attributes_with_stable_attributes
        txn = in_transaction(request: {}) do |t|
          t
        end

        attributes = {
          'server.address' => 'example.com',
          'http.request.method' => 'GET',
          'url.path' => '/api/users',
          'user_agent.original' => 'Mozilla/5.0'
        }

        @test_instance.update_request_attributes(txn, attributes)

        request_attributes = txn.instance_variable_get(:@request_attributes)

        assert_equal 'example.com', request_attributes.instance_variable_get(:@host)
        assert_equal 'GET', request_attributes.instance_variable_get(:@request_method)
        assert_equal '/api/users', request_attributes.instance_variable_get(:@request_path)
        assert_equal 'Mozilla/5.0', request_attributes.instance_variable_get(:@user_agent)
      end

      def test_update_request_attributes_with_old_attributes
        txn = in_transaction(request: {}) do |t|
          t
        end

        attributes = {
          'http.host' => 'old.example.com',
          'http.method' => 'POST',
          'http.target' => '/api/posts',
          'http.user_agent' => 'Chrome/144.0'
        }

        @test_instance.update_request_attributes(txn, attributes)

        request_attributes = txn.instance_variable_get(:@request_attributes)

        assert_equal 'old.example.com', request_attributes.instance_variable_get(:@host)
        assert_equal 'POST', request_attributes.instance_variable_get(:@request_method)
        assert_equal '/api/posts', request_attributes.instance_variable_get(:@request_path)
        assert_equal 'Chrome/144.0', request_attributes.instance_variable_get(:@user_agent)
      end

      def test_update_request_attributes_prefers_stable_attributes
        txn = in_transaction(request: {}) do |t|
          t
        end

        # Mix of stable and old attributes - stable should be preferred
        attributes = {
          'server.address' => 'stable.example.com',
          'http.host' => 'old.example.com',
          'http.request.method' => 'PUT',
          'http.method' => 'GET',
          'url.path' => '/stable/path',
          'http.target' => '/old/path',
          'user_agent.original' => 'Firefox/144.0',
          'http.user_agent' => 'Safari/144.0'
        }

        @test_instance.update_request_attributes(txn, attributes)

        request_attributes = txn.instance_variable_get(:@request_attributes)

        assert_equal 'stable.example.com', request_attributes.instance_variable_get(:@host)
        assert_equal 'PUT', request_attributes.instance_variable_get(:@request_method)
        assert_equal '/stable/path', request_attributes.instance_variable_get(:@request_path)
        assert_equal 'Firefox/144.0', request_attributes.instance_variable_get(:@user_agent)
      end

      def test_update_request_attributes_with_partial_attributes
        txn = in_transaction(request: {}) do |t|
          t
        end

        request_attributes = txn.instance_variable_get(:@request_attributes)
        original_path = request_attributes.instance_variable_get(:@request_path)
        original_user_agent = request_attributes.instance_variable_get(:@user_agent)

        attributes = {
          'server.address' => 'example.com',
          'http.request.method' => 'DELETE'
        }

        @test_instance.update_request_attributes(txn, attributes)

        assert_equal 'example.com', request_attributes.instance_variable_get(:@host)
        assert_equal 'DELETE', request_attributes.instance_variable_get(:@request_method)

        assert_equal original_path, request_attributes.instance_variable_get(:@request_path)
        assert_equal original_user_agent, request_attributes.instance_variable_get(:@user_agent)
      end

      def test_update_request_attributes_with_nil_attributes
        txn = in_transaction(request: {}) do |t|
          t
        end

        @test_instance.update_request_attributes(txn, nil)

        request_attributes = txn.instance_variable_get(:@request_attributes)

        assert_instance_of NewRelic::Agent::Transaction::RequestAttributes, request_attributes
      end

      def test_update_request_attributes_does_not_update_non_transaction
        segment = NewRelic::Agent::Transaction::Segment.new

        attributes = {
          'server.address' => 'example.com',
          'http.request.method' => 'GET'
        }

        result = @test_instance.update_request_attributes(segment, attributes)

        assert_nil result
      end

      def test_update_request_attributes_does_not_update_without_request_attributes
        mock_txn = Object.new
        mock_txn.instance_variable_set(:@request_attributes, nil)

        attributes = {
          'server.address' => 'example.com'
        }

        result = @test_instance.update_request_attributes(mock_txn, attributes)

        assert_nil result
      end
    end
  end
end
