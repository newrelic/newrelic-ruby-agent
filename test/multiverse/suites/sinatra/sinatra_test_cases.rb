# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

# This module brings the base test cases that should run against both classic and
# module Sinatra apps. The sinatra_class_test and sinatra_modular_test files
# both maintain the same app structure in both forms, and this exercises them.

module SinatraTestCases
  include Rack::Test::Methods
  include MultiverseHelpers

  module SinatraRouteNaming
    # get '/route/:name'
    def route_name_segment
      'GET /route/:name'
    end

    # get '/route/no_match'
    def route_no_match_segment
      'GET /route/no_match'
    end

    if Gem::Version.new(Sinatra::VERSION).segments[0] < 2
      # get /\/regex.*/
      def regex_segment
        'GET (?-mix:\/regex.*)'
      end
    else
      def regex_segment
        'GET \/regex.*'
      end
    end

    # get '/precondition'
    def precondition_segment
      'GET /precondition'
    end

    #get '/ignored'
    def ignored_segment
      'GET /ignored'
    end
  end

  module NRRouteNaming
    # get '/route/:name'
    def route_name_segment
      'GET route/([^/?#]+)'
    end

    # get '/route/no_match'
    def route_no_match_segment
      'GET route/no_match'
    end

    # get /\/regex.*/
    def regex_segment
      'GET regex.*'
    end

    # get '/precondition'
    def precondition_segment
      'GET precondition'
    end

    #get '/ignored'
    def ignored_segment
      'GET ignored'
    end
  end

  if Sinatra::VERSION >= '1.4.3'
    include SinatraRouteNaming
  else
    include NRRouteNaming
  end

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
     errors = harvest_error_traces!
     assert_equal 1, errors.size
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
    errors = harvest_error_traces!
    assert_equal 1, errors.size
  end

  def test_correct_pattern
    get '/route/match'
    assert_equal 'first route', last_response.body
    assert_metrics_recorded(["Controller/Sinatra/#{app_name}/#{route_name_segment}"])
  end

  def test_finds_second_route
    get '/route/no_match'
    assert_equal 'second route', last_response.body
    assert_metrics_recorded(["Controller/Sinatra/#{app_name}/#{route_no_match_segment}"])
  end

  def test_with_regex_pattern
    get '/regexes'
    assert_equal "Yeah, regex's!", last_response.body
    assert_metrics_recorded(["Controller/Sinatra/#{app_name}/#{regex_segment}"])
  end

  # this test is not applicable to environments that use sinatra.route for txn naming
  if self.include? NRRouteNaming
    def test_set_unknown_transaction_name_if_error_in_routing
      ::NewRelic::Agent::Instrumentation::Sinatra::TransactionNamer \
        .stubs(:http_verb).raises(StandardError.new('madness'))

      get '/user/login'
      assert_metrics_recorded(["Controller/Sinatra/#{app_name}/(unknown)"])
    end
  end

  # https://support.newrelic.com/tickets/31061
  def test_precondition_not_over_called
    get '/precondition'

    assert_equal 200, last_response.status
    assert_equal 'precondition only happened once', last_response.body
    assert_metrics_recorded(["Controller/Sinatra/#{app_name}/#{precondition_segment}"])
  end

  def test_filter
    get '/filtered'

    assert_equal 200, last_response.status
    assert_equal 'got filtered', last_response.body
  end

  def test_ignores_route_metrics
    get '/ignored'

    assert_equal 200, last_response.status
    assert_metrics_not_recorded(["Controller/Sinatra/#{app_name}/#{ignored_segment}"])
  end

  def test_rack_request_params_errors_are_swallowed
    trigger_error_on_params

    get '/pass'

    expected_status = Gem::Version.new(Sinatra::VERSION).segments[0] < 2 ? 200 : 400

    assert_equal expected_status, last_response.status
  end

  def test_rack_request_params_errors_are_logged
    NewRelic::Agent.logger.stubs(:debug)
    NewRelic::Agent.logger.expects(:debug).with("Failed to get params from Rack request.", kind_of(StandardError)).at_least_once

    trigger_error_on_params

    get '/pass'
  end

  def test_injects_middleware
    app.stubs(:middleware).returns([])

    app.expects(:build_without_newrelic).once
    app.expects(:use).at_least(2)

    app.build_with_newrelic(@app)
  end

  def test_doesnt_inject_already_existing_middleware
    default_middlewares = app.newrelic_middlewares
    # mock up the return value of Sinatra's #middleware method, which returns an
    # Array of Arrays.
    middleware_info = default_middlewares.map { |m| [m] }
    app.stubs(:middleware).returns(middleware_info)

    app.expects(:build_without_newrelic).once
    app.expects(:use).never

    app.build_with_newrelic(@app)
  end

  if Gem::Version.new(Sinatra::VERSION).segments[0] < 2
    def trigger_error_on_params
      Sinatra::Request.any_instance.
      stubs(:params).returns({}).
      then.raises(StandardError.new "Rack::Request#params error")
    end
  else
    def trigger_error_on_params
      Sinatra::Request.any_instance.
      stubs(:params).
      raises(Sinatra::BadRequest.new)
    end
  end

  def test_root_path_naming
    get '/'

    assert_metrics_recorded ["Controller/Sinatra/#{app_name}/GET /"]
    refute_metrics_recorded ["Controller/Sinatra/#{app_name}/GET "]
  end
end
