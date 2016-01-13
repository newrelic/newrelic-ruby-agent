# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class SinatraIgnoreTestApp < Sinatra::Base
  get '/record' do request.path_info end

  newrelic_ignore '/ignore'
  get '/ignore' do request.path_info end

  newrelic_ignore '/splat*'
  get '/splattered' do request.path_info end

  newrelic_ignore '/named/:id'
  get '/named/:id' do request.path_info end

  newrelic_ignore '/v1', '/v2'
  get '/v1' do request.path_info end
  get '/v2' do request.path_info end
  get '/v3' do request.path_info end

  newrelic_ignore(/\/.+regex.*/)
  get '/skip_regex' do request.path_info end
  get '/regex_seen' do request.path_info end

  newrelic_ignore '/ignored_erroring'
  get '/ignored_erroring' do raise 'boom'; end

  newrelic_ignore_apdex '/no_apdex'
  get '/no_apdex' do request.path_info end

  newrelic_ignore_enduser '/no_enduser'

  get '/enduser' do
    "<html><head></head><body>#{request.path_info}</body></html>"
  end

  get '/no_enduser' do
    "<html><head></head><body>#{request.path_info}</body></html>"
  end
end

class SinatraTestCase < Minitest::Test
  include Rack::Test::Methods
  include ::NewRelic::Agent::Instrumentation::Sinatra
  include MultiverseHelpers

  JS_AGENT_LOADER = "JS_AGENT_LOADER"

  setup_and_teardown_agent(:application_id => 'appId',
                           :beacon => 'beacon',
                           :browser_key => 'browserKey',
                           :js_agent_loader => JS_AGENT_LOADER)

  def get_and_assert_ok(path)
    get(path)
    assert_equal 200, last_response.status
    assert_match(/#{Regexp.escape(path)}/, last_response.body)
  end

  def assert_enduser_ignored(response)
    refute_match(/#{JS_AGENT_LOADER}/, response.body)
  end

  def refute_enduser_ignored(response)
    assert_match(/#{JS_AGENT_LOADER}/, response.body)
  end

  # Keep Test::Unit happy by specifying at least one test method here
  # Real tests are defined in subclasses.
  def test_nothing; end
end

class SinatraIgnoreTest < SinatraTestCase
  def app
    SinatraIgnoreTestApp
  end

  def app_name
    app.to_s
  end

  def test_seen_route
    get_and_assert_ok '/record'
    segment = name_for_route 'record'
    assert_metrics_recorded([
      "Controller/Sinatra/#{app_name}/#{segment}",
      "Apdex/Sinatra/#{app_name}/#{segment}"])
  end

  def test_ignores_exact_match
    get_and_assert_ok '/ignore'
    segment = name_for_route 'ignore'
    assert_metrics_not_recorded([
      "Controller/Sinatra/#{app_name}/#{segment}",
      "Apdex/Sinatra/#{app_name}/#{segment}"])
  end

  def test_ignores_by_splats
    get_and_assert_ok '/splattered'
    segment = name_for_route 'splattered'
    assert_metrics_not_recorded([
      "Controller/Sinatra/#{app_name}/#{segment}",
      "Apdex/Sinatra/#{app_name}/#{segment}"])
  end

  def test_ignores_can_be_declared_in_batches
    get_and_assert_ok '/v1'
    get_and_assert_ok '/v2'
    get_and_assert_ok '/v3'

    v1_segment = name_for_route 'v1'
    v2_segment = name_for_route 'v2'
    v3_segment = name_for_route 'v3'

    assert_metrics_not_recorded([
      "Controller/Sinatra/#{app_name}/#{v1_segment}",
      "Controller/Sinatra/#{app_name}/#{v2_segment}",
      "Apdex/Sinatra/#{app_name}/#{v1_segment}",
      "Apdex/Sinatra/#{app_name}/#{v2_segment}"])

    assert_metrics_recorded([
      "Controller/Sinatra/#{app_name}/#{v3_segment}",
      "Apdex/Sinatra/#{app_name}/#{v3_segment}"])
  end

  def test_seen_with_regex
    get_and_assert_ok '/regex_seen'
    segment = name_for_route 'regex_seen'
    assert_metrics_recorded([
      "Controller/Sinatra/#{app_name}/#{segment}",
      "Apdex/Sinatra/#{app_name}/#{segment}"])
  end

  def test_ignores_by_regex
    get_and_assert_ok '/skip_regex'
    segment = name_for_route 'skip_regex'
    assert_metrics_not_recorded([
      "Controller/Sinatra/#{app_name}/#{segment}",
      "Apdex/Sinatra/#{app_name}/#{segment}"])
  end

  def test_ignore_apdex
    get_and_assert_ok '/no_apdex'
    segment = name_for_route 'no_apdex'
    assert_metrics_recorded(["Controller/Sinatra/#{app_name}/#{segment}"])
    assert_metrics_not_recorded(["Apdex/Sinatra/#{app_name}/#{segment}"])
  end

  def test_ignore_enduser_should_only_apply_to_specified_route
    get_and_assert_ok '/enduser'
    segment = name_for_route 'enduser'
    refute_enduser_ignored(last_response)
    assert_metrics_recorded([
      "Controller/Sinatra/#{app_name}/#{segment}",
      "Apdex/Sinatra/#{app_name}/#{segment}"])
  end

  def test_ignore_enduser
    get_and_assert_ok '/no_enduser'
    segment = name_for_route 'no_enduser'
    assert_enduser_ignored(last_response)
    assert_metrics_recorded([
      "Controller/Sinatra/#{app_name}/#{segment}",
      "Apdex/Sinatra/#{app_name}/#{segment}"])
  end

  def test_ignore_errors_in_ignored_transactions
    get '/ignored_erroring'
    assert_metrics_not_recorded(["Errors/all"])
  end

  def name_for_route path
    if last_request.env.key? 'sinatra.route'
      "GET /#{path}"
    else
      "GET #{path}"
    end
  end
end

# Blanket ignore for whole app if newrelic_ignore called without parameters
class SinatraIgnoreItAllApp < Sinatra::Base
  newrelic_ignore

  get '/' do request.path_info end
end

class SinatraIgnoreItAllTest < SinatraTestCase
  def app
    SinatraIgnoreItAllApp
  end

  def test_ignores_everything
    # Avoid Supportability metrics from startup of agent for this check
    NewRelic::Agent.drop_buffered_data

    get_and_assert_ok '/'
    assert_metrics_recorded_exclusive([])
  end
end


# Blanket ignore for whole app if calls made without parameters
class SinatraIgnoreApdexAndEndUserApp < Sinatra::Base
  newrelic_ignore_apdex
  newrelic_ignore_enduser

  get '/' do request.path_info end
end

class SinatraIgnoreApdexAndEndUserTest < SinatraTestCase
  def app
    SinatraIgnoreApdexAndEndUserApp
  end

  def test_ignores_apdex
    get_and_assert_ok '/'
    assert_metrics_not_recorded(["Apdex/Sinatra/#{app.to_s}/GET /"])
  end

  def test_ignores_enduser
    get_and_assert_ok '/'
    assert_enduser_ignored(last_response)
  end
end
