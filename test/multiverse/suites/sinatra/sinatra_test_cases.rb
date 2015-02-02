# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# This module brings the base test cases that should run against both classic and
# module Sinatra apps. The sinatra_class_test and sinatra_modular_test files
# both maintain the same app structure in both forms, and this exercises them.

require 'multiverse_helpers'

module SinatraTestCases
  include Rack::Test::Methods
  include MultiverseHelpers


  def app
    raise "Must implement app on your test case"
  end

  def app_name
    app.to_s
  end

  setup_and_teardown_agent

  def after_setup
    $precondition_already_checked = false
  end

  # https://support.newrelic.com/tickets/24779
  def test_lower_priority_route_conditions_arent_applied_to_higher_priority_routes
    get '/user/login'
    assert_equal 200, last_response.status
    assert_equal 'please log in', last_response.body
  end

  def test_conditions_are_applied_to_an_action_that_uses_them
    get '/user/1'
    assert_equal 404, last_response.status
  end

  def test_queue_time_headers_are_passed_to_agent
    get '/user/login', {}, { 'HTTP_X_REQUEST_START' => 't=1360973845' }
    assert_metrics_recorded(["WebFrontend/QueueTime"])
  end

  def test_shown_errors_get_caught
     get '/raise'
     assert_equal 1, ::NewRelic::Agent.agent.error_collector.errors.size
  end

  def test_does_not_break_pass
    get '/pass'
    assert_equal 200, last_response.status
    assert_equal "I'm not a teapot.", last_response.body
  end

  def test_does_not_break_error_handling
    get '/error'
    assert_equal 200, last_response.status
    assert_equal "nothing happened", last_response.body
  end

  def test_sees_handled_error
    get '/error'
    assert_equal 1, ::NewRelic::Agent.agent.error_collector.errors.size
  end

  def test_correct_pattern
    get '/route/match'
    assert_equal 'first route', last_response.body
    assert_metrics_recorded(["Controller/Sinatra/#{app_name}/GET route/([^/?#]+)"])
  end

  def test_finds_second_route
    get '/route/no_match'
    assert_equal 'second route', last_response.body
    assert_metrics_recorded(["Controller/Sinatra/#{app_name}/GET route/no_match"])
  end

  def test_with_regex_pattern
    get '/regexes'
    assert_equal "Yeah, regex's!", last_response.body
    assert_metrics_recorded(["Controller/Sinatra/#{app_name}/GET regex.*"])
  end

  def test_set_unknown_transaction_name_if_error_in_routing
    ::NewRelic::Agent::Instrumentation::Sinatra::TransactionNamer \
      .stubs(:http_verb).raises(StandardError.new('madness'))

    get '/user/login'
    assert_metrics_recorded(["Controller/Sinatra/#{app_name}/(unknown)"])
  end

  # https://support.newrelic.com/tickets/31061
  def test_precondition_not_over_called
    get '/precondition'

    assert_equal 200, last_response.status
    assert_equal 'precondition only happened once', last_response.body
    assert_metrics_recorded(["Controller/Sinatra/#{app_name}/GET precondition"])
  end

  def test_filter
    get '/filtered'

    assert_equal 200, last_response.status
    assert_equal 'got filtered', last_response.body
  end

  def test_ignores_route_metrics
    get '/ignored'

    assert_equal 200, last_response.status
    assert_metrics_not_recorded(["Controller/Sinatra/#{app_name}/GET ignored"])
  end

  def test_rack_request_params_errors_are_swallowed
    fail_on_second_params_call

    get '/pass'
    assert_equal 200, last_response.status
  end

  def test_rack_request_params_errors_are_logged
    NewRelic::Agent.logger.stubs(:debug)
    NewRelic::Agent.logger.expects(:debug).with("Failed to get params from Rack request.", kind_of(StandardError)).at_least_once

    fail_on_second_params_call

    get '/pass'
  end

  def test_file_upload_params_are_filtered
    with_config(:capture_params => true) do
      params = {
        :title => "blah",
        :file => Rack::Test::UploadedFile.new(__FILE__, 'text/plain')
      }
      post '/files', params
      assert_equal({"title" => "blah", "file" => "[FILE]"}, last_transaction_trace_request_params)
    end
  end

  def fail_on_second_params_call
    Sinatra::Request.any_instance.
      stubs(:params).returns({}).
      then.raises("Rack::Request#params error")
  end
end
