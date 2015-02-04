# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "grape"
require "newrelic_rpm"
require 'multiverse_helpers'
require './grape_test_api'

require File.join(File.dirname(__FILE__), "..", "..", "..", "agent_helper")

class GrapeTest < Minitest::Test
  include Rack::Test::Methods
  include MultiverseHelpers

  setup_and_teardown_agent

  unless ::Grape::VERSION == '0.1.5'
    def app
      Rack::Builder.app { run GrapeTestApi.new }
    end

    def test_nonexistent_route
      get '/not_grape_ape'
      assert_no_metrics_match(/grape_ape/)
    end

    def test_route_raises_an_error
      assert_raises(GrapeTestApiError) do
        get '/self_destruct'
      end

      expected_txn_name = 'Controller/Grape/GrapeTestApi/self_destruct (GET)'
      assert_grape_metrics(expected_txn_name)
      assert_metrics_recorded(["Errors/#{expected_txn_name}"])
    end

    def test_getting_a_list_of_grape_apes
      get '/grape_ape'
      assert_grape_metrics('Controller/Grape/GrapeTestApi/grape_ape (GET)')
    end

    def test_showing_a_grape_ape
      get '/grape_ape/1'
      assert_grape_metrics('Controller/Grape/GrapeTestApi/grape_ape/:id (GET)')
    end

    def test_creating_a_grape_ape
      post '/grape_ape', {}
      assert_grape_metrics('Controller/Grape/GrapeTestApi/grape_ape (POST)')
    end

    def test_updating_a_grape_ape
      put '/grape_ape/1', {}
      assert_grape_metrics('Controller/Grape/GrapeTestApi/grape_ape/:id (PUT)')
    end

    def test_deleting_a_grape_ape
      delete '/grape_ape/1'
      assert_grape_metrics('Controller/Grape/GrapeTestApi/grape_ape/:id (DELETE)')
    end

    def test_transaction_renaming
      get '/grape_ape/renamed'
      # The second segment here is 'Rack' because of an idiosyncrasy of
      # the set_transaction_name API: when you call set_transaction_name and
      # don't provide an explicit category, you lock in the category prefix
      # that was in use at the time you made the call.
      #
      # We may change this behavior in the future, once we have a better
      # internal representation of the name and category of a transaction as
      # truly separate entities.
      #
      assert_grape_metrics('Controller/Rack/RenamedTxn')
      #assert_metrics_recorded(['Controller/Rack/RenamedTxn'])
    end

    def test_params_are_not_captured_with_capture_params_disabled
      with_config(:capture_params => false) do
        get '/grape_ape/10'
        assert_equal({}, last_transaction_trace_request_params)
      end
    end

    def test_route_params_are_captured
      with_config(:capture_params => true) do
        get '/grape_ape/10'
        assert_equal({"id" => "10"}, last_transaction_trace_request_params)
      end
    end

    def test_query_params_are_captured
      with_config(:capture_params => true) do
        get '/grape_ape?q=1234&foo=bar'
        assert_equal({'q' => '1234', 'foo' => 'bar'}, last_transaction_trace_request_params)
      end
    end

    def test_post_body_params_are_captured
      with_config(:capture_params => true) do
        post '/grape_ape', {'q' => '1234', 'foo' => 'bar'}.to_json, "CONTENT_TYPE" => "application/json"
        assert_equal({'q' => '1234', 'foo' => 'bar'}, last_transaction_trace_request_params)
      end
    end

    def test_post_body_with_nested_params_are_captured
      with_config(:capture_params => true) do
        params = {"ape" => {"first_name" => "koko", "last_name" => "gorilla"}}
        post '/grape_ape', params.to_json, "CONTENT_TYPE" => "application/json"
        assert_equal(params, last_transaction_trace_request_params)
      end
    end

    def test_file_upload_params_are_filtered
      with_config(:capture_params => true) do
        params = {
          :title => "blah",
          :file => Rack::Test::UploadedFile.new(__FILE__, 'text/plain')
        }
        post '/grape_ape', params
        assert_equal({"title" => "blah", "file" => "[FILE]"}, last_transaction_trace_request_params)
      end
    end

    def test_404_with_params_does_not_capture_them
      with_config(:capture_params => true) do
        post '/grape_catfish', {"foo" => "bar"}
        assert_equal({}, last_transaction_trace_request_params)
      end
    end

    def assert_grape_metrics(expected_txn_name)
      expected_segment_name = 'Middleware/Grape/GrapeTestApi/call'
      assert_metrics_recorded([
        expected_segment_name,
        [expected_segment_name, expected_txn_name],
        expected_txn_name
      ])
    end
  end
end
