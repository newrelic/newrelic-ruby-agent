# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'mocha'

class SinatraRouteTestApp < Sinatra::Base
  configure do
    # display exceptions so we see what's going on
    disable :show_exceptions

    # create a condition (sintra's version of a before_filter) that returns the
    # value that was passed into it.
    set :my_condition do |boolean|
      condition do
        halt 404 unless boolean
      end
    end
  end

  get '/user/login' do
    "please log in"
  end

  # this action will always return 404 because of the condition.
  get '/user/:id', :my_condition => false do |id|
    "Welcome #{id}"
  end

  get '/raise' do
    raise "Uh-oh"
  end

  # check that pass works properly
  condition { pass { halt 418, "I'm a teapot." } }
  get('/pass') { }

  get '/pass' do
    "I'm not a teapot."
  end

  class Error < StandardError; end
  error(Error) { halt 200, 'nothing happened' }
  condition { raise Error }
  get('/error') { }

  def perform_action_with_newrelic_trace(options)
    $last_sinatra_route = options[:name]
    super
  end

  get '/route/:name' do |name|
    # usually this would be a db test or something
    pass if name != 'match'
    'first route'
  end

  get '/route/no_match' do
    'second route'
  end
end

class SinatraTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include ::NewRelic::Agent::Instrumentation::Sinatra

  def app
    SinatraRouteTestApp
  end

  def setup
    ::NewRelic::Agent.manual_start
  end

  def teardown
    ::NewRelic::Agent.agent.error_collector.harvest_errors([])
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
    assert ::NewRelic::Agent.agent.stats_engine.lookup_stats('WebFrontend/QueueTime')
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
    assert_equal 'GET route/([^/?#]+)', $last_sinatra_route

    get '/route/no_match'
    assert_equal 'second route', last_response.body

    # Ideally we could handle this assert, but we can't rename transactions
    # in flight at this point. Once we get that ability, consider patching
    # process_route to notify of route name changes.

    # assert_equal 'GET route/no_match', $last_sinatra_route
  end

  def test_set_unknown_transaction_name_if_error_in_routing
    ::NewRelic::Agent::Instrumentation::Sinatra::NewRelic \
      .stubs(:http_verb).raises(StandardError.new('madness'))

    get '/user/login'

    metric_names = ::NewRelic::Agent.agent.stats_engine.metrics
    assert(metric_names.include?('Controller/Sinatra/SinatraRouteTestApp/(unknown)'),
           "#{metric_names} should include 'Controller/Sinatra/SinatraRouteTestApp/(unknown)'")
  end
end
