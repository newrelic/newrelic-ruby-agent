# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require './app'

class ParameterCaptureController < ApplicationController
  def transaction
    render :text => 'hi!'
  end

  def create
    raise 'problem' if params[:raise]
    render :text => 'created'
  end

  def sql
    NewRelic::Agent.agent.sql_sampler.notice_sql(
      'SELECT * FROM table',
      'ActiveRecord/foos/find',
      {},
      100.0
    )
  end

  def error
    raise 'wut'
  end

  # For Rails 3+, this is configured globally in the config block for the app
  if Rails::VERSION::MAJOR == 2
    filter_parameter_logging(:secret)
  end
end

class ParameterCaptureTest < RailsMultiverseTest
  include MultiverseHelpers
  setup_and_teardown_agent

  def test_no_params_captured_on_errors_when_disabled
    with_config(:capture_params => false) do
      get '/parameter_capture/error?other=1234&secret=4567'
      refute_contains_request_params(agent_attributes_for_single_error_posted)
    end
  end

  def test_no_params_captured_on_tts_when_disabled
    with_config(:capture_params => false) do
      get '/parameter_capture/transaction?other=1234&secret=4567'
    end
    assert_equal({}, last_transaction_trace_request_params)
  end

  def test_uri_on_traced_errors_never_contains_query_string_without_capture_params
    with_config(:capture_params => false) do
      get '/parameter_capture/error?other=1234&secret=4567'
      assert_equal('/parameter_capture/error', attributes_for_single_error_posted("request_uri"))
    end
  end

  def test_uri_on_traced_errors_never_contains_query_string_with_capture_params
    with_config(:capture_params => true) do
      get '/parameter_capture/error?other=1234&secret=4567'
      assert_equal('/parameter_capture/error', attributes_for_single_error_posted("request_uri"))
    end
  end

  def test_referrer_on_traced_errors_never_contains_query_string_without_capture_params
    with_config(:capture_params => false) do
      get '/parameter_capture/error?other=1234&secret=4567', {}, { 'HTTP_REFERER' => '/foo/bar?other=123&secret=456' }
      attributes = agent_attributes_for_single_error_posted
      assert_equal('/foo/bar', attributes["request.headers.referer"])
    end
  end

  def test_referrer_on_traced_errors_never_contains_query_string_even_with_capture_params
    with_config(:capture_params => true) do
      get '/parameter_capture/error?other=1234&secret=4567', {}, { 'HTTP_REFERER' => '/foo/bar?other=123&secret=456' }
      attributes = agent_attributes_for_single_error_posted
      assert_equal('/foo/bar', attributes["request.headers.referer"])
    end
  end

  def test_controller_and_action_excluded_from_error_parameters
    with_config(:capture_params => true) do
      get '/parameter_capture/error'
      run_harvest

      refute_error_has_agent_attribute('request.parameters.controller')
      refute_error_has_agent_attribute('request.parameters.action')
    end
  end

  def test_controller_and_action_excluded_from_transaction_trace_parameters
    with_config(:capture_params => true, :'transaction_tracer.transaction_threshold' => -10) do
      get '/parameter_capture/transaction'
      run_harvest

      refute_transaction_trace_has_agent_attribute('request.parameters.controller')
      refute_transaction_trace_has_agent_attribute('request.parameters.action')
    end
  end

  def test_uri_on_tts_never_contains_query_string
    with_config(:capture_params => false) do
      get '/parameter_capture/transaction?other=1234&secret=4567'
    end
    assert_equal('/parameter_capture/transaction', last_transaction_trace.uri)

    with_config(:capture_params => true) do
      get '/parameter_capture/transaction?other=1234&secret=4567'
    end
    assert_equal('/parameter_capture/transaction', last_transaction_trace.uri)
  end

  def test_filters_parameters_on_traced_errors
    with_config(:capture_params => true) do
      get '/parameter_capture/error?other=1234&secret=4567'

      captured_params = agent_attributes_for_single_error_posted
      assert_equal('[FILTERED]', captured_params['request.parameters.secret'])
      assert_equal('1234',       captured_params['request.parameters.other'])
    end
  end

  def test_filters_parameters_on_transaction_traces
    with_config(:capture_params => true) do
      get '/parameter_capture/transaction?other=1234&secret=4567'
    end

    captured_params = last_transaction_trace_request_params
    assert_equal('[FILTERED]', captured_params['request.parameters.secret'])
    assert_equal('1234',       captured_params['request.parameters.other'])
  end

  def test_no_traced_error_params_captured_when_bails_before_rails
    with_config(:capture_params => false) do
      get '/middleware_error/before?other=1234&secret=4567'
      refute_contains_request_params(agent_attributes_for_single_error_posted)
    end
  end

  def test_no_transaction_trace_params_captured_when_bails_before_rails
    with_config(:capture_params => false) do
      get '/middleware_error/before?other=1234&secret=4567'
    end

    assert_equal({}, last_transaction_trace_request_params)
  end

  def test_no_params_captured_on_error_when_bails_before_rails_even_when_enabled
    with_config(:capture_params => true) do
      get '/middleware_error/before?other=1234&secret=4567'
      refute_contains_request_params(agent_attributes_for_single_error_posted)
    end
  end

  def test_no_params_captured_on_tt_when_bails_before_rails_even_when_enabled
    with_config(:capture_params => true) do
      get '/middleware_error/before?other=1234&secret=4567'
    end
    assert_equal({}, last_transaction_trace_request_params)
  end

  def test_uri_on_tt_should_not_contain_query_string_with_capture_params_off
    with_config(:capture_params => false) do
      get '/parameter_capture/transaction?param1=value1&param2=value2'
    end
    assert_equal('/parameter_capture/transaction', last_transaction_trace.uri)
  end

  def test_uri_on_tt_should_not_contain_query_string_with_capture_params_on
    with_config(:capture_params => true) do
      get '/parameter_capture/transaction?param1=value1&param2=value2'
    end
    assert_equal('/parameter_capture/transaction', last_transaction_trace.uri)
  end

  def test_uri_on_traced_error_should_not_contain_query_string_with_capture_params_off
    with_config(:capture_params => false) do
      get '/parameter_capture/error?param1=value1&param2=value2'
      assert_equal('/parameter_capture/error', attributes_for_single_error_posted("request_uri"))
    end
  end

  def test_uri_on_traced_error_should_not_contain_query_string_with_capture_params_on
    with_config(:capture_params => true) do
      get '/parameter_capture/error?param1=value1&param2=value2'
      assert_equal('/parameter_capture/error', attributes_for_single_error_posted("request_uri"))
    end
  end

  def test_uri_on_sql_trace_should_not_contain_query_string_with_capture_params_off
    with_config(:capture_params => false) do
      get '/parameter_capture/sql?param1=value1&param2=value2'
    end
    assert_equal('/parameter_capture/sql', last_sql_trace.url)
  end

  def test_uri_on_sql_trace_should_not_contain_query_string_with_capture_params_on
    with_config(:capture_params => true) do
      get '/parameter_capture/sql?param1=value1&param2=value2'
    end
    assert_equal('/parameter_capture/sql', last_sql_trace.url)
  end

  def test_parameters_attached_to_transaction_events_if_enabled
    with_config(:'attributes.include' => 'request.parameters.*',
                :'attributes.exclude' => ['request.*', 'response.*']) do
      get '/parameter_capture/transaction?param1=value1&param2=value2'
    end

    actual = agent_attributes_for_single_event_posted_without_ignored_attributes

    expected = {"request.parameters.param1" => "value1",
      "request.parameters.param2" => "value2"
    }

    assert_equal expected, actual
  end

  def test_request_and_response_attributes_recorded_as_agent_attributes
      get '/parameter_capture/transaction'

      expected = {
        "response.headers.contentType" => "#{response.content_type}; charset=#{response.charset}",
        "request.headers.contentLength" => request.content_length.to_i,
        "request.headers.contentType" => request.content_type,
        "request.headers.host" => request.host,
        "request.headers.accept" => request.accept
      }

      # ActionController::IntegrationTest sets this header whereas ActionDispatch::IntegrationTest
      # does not. Since we test using both we need to conditionally expect content_length to be set.

      unless defined?(ActionDispatch::IntegrationTest)
        expected["response.headers.contentLength"] = response.content_length
      end

      actual = agent_attributes_for_single_event_posted_without_ignored_attributes

      # request method may be a symbol or string based on Rails versions
      request_method = actual.delete("request.method")
      assert_equal request_method, request.request_method.to_s.upcase

      assert_equal(expected, actual)
  end


  if Rails::VERSION::MAJOR > 2
    def test_params_tts_should_be_filtered_when_serviced_by_rack_app
      params = {"secret" => "shhhhhhh", "name" => "name"}
      with_config(:capture_params => true) do
        post '/filtering_test/', params
      end

      expected = {
        "request.parameters.secret" => "[FILTERED]",
        "request.parameters.name" => "name"
      }
      assert_equal expected, last_transaction_trace_request_params
    end

    def test_params_on_errors_should_be_filtered_when_serviced_by_rack_app
      params = {"secret" => "shhhhhhh", "name" => "name"}
      with_config(:capture_params => true) do
        post '/filtering_test?raise=1', params

        expected = {
          "request.parameters.secret" => "[FILTERED]",
          "request.parameters.name" => "name",
          "request.parameters.raise" => "1"
        }

        attributes = agent_attributes_for_single_error_posted
        expected.each do |key, value|
          assert_equal value, attributes[key]
        end
      end
    end

    def test_parameter_filtering_should_not_mutate_argument
      input = { "foo" => "bar", "secret" => "baz" }
      env   = { "action_dispatch.parameter_filter" => ["secret"] }
      filtered = NewRelic::Agent::ParameterFiltering.apply_filters(env, input)

      assert_equal({ "foo" => "bar", "secret" => "[FILTERED]" }, filtered)
      assert_equal({ "foo" => "bar", "secret" => "baz" }, input)
    end
  end

  if Rails::VERSION::MAJOR > 2 && defined?(Sinatra)
    def test_params_tts_should_be_filtered_when_serviced_by_sinatra_app
      with_config(:capture_params => true) do
        get '/sinatra_app/', "secret" => "shhhhhhh", "name" => "name"
      end

      expected = {
        "request.parameters.secret" => "[FILTERED]",
        "request.parameters.name" => "name"
      }
      assert_equal expected, last_transaction_trace_request_params
    end

    def test_params_on_errors_should_be_filtered_when_serviced_by_sinatra_app
      with_config(:capture_params => true) do
        get '/sinatra_app?raise=1', "secret" => "shhhhhhh", "name" => "name"

        attributes = agent_attributes_for_single_error_posted
        assert_equal "[FILTERED]", attributes["request.parameters.secret"]
        assert_equal "name", attributes["request.parameters.name"]
        assert_equal "1", attributes["request.parameters.raise"]
      end
    end

    def test_file_upload_params_are_replaced_with_placeholder
      with_config(:capture_params => true, :'transaction_tracer.transaction_threshold' => -10) do
        post '/parameter_capture', :file => Rack::Test::UploadedFile.new(__FILE__, 'text/plain')

        run_harvest

        result = single_transaction_trace_posted
        assert_equal "#<ActionDispatch::Http::UploadedFile>", result.agent_attributes["request.parameters.file"]
      end
    end
  end

end
