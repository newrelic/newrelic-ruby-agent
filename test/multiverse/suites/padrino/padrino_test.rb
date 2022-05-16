# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

# Shhhh
Padrino::Logger::Config[:development][:stream] = :null

class PadrinoTestApp < Padrino::Application
  register Padrino::Rendering
  register Padrino::Routing
  register Padrino::Helpers

  get '/user/login' do
    "please log in"
  end

  get(/\/regex.*/) do
    "with extra regexes please!"
  end
end

class PadrinoRoutesTest < Minitest::Test
  include Rack::Test::Methods
  include Mocha::API

  def app
    PadrinoTestApp
  end

  include MultiverseHelpers

  setup_and_teardown_agent

  def setup
    mocha_setup
  end

  def teardown
    mocha_teardown
  end

  def test_tracing_is_involved
    klass = ENV['MULTIVERSE_INSTRUMENTATION_METHOD'] == 'chain' ? ::PadrinoTestApp : ::Padrino::Application
    klass.any_instance.expects(:invoke_route_with_tracing)
    get '/user/login'
  end

  def test_basic_route
    get '/user/login'
    assert_equal 200, last_response.status
    assert_equal 'please log in', last_response.body

    assert_metrics_recorded([
      "Controller/Sinatra/PadrinoTestApp/GET user/login",
      "Apdex/Sinatra/PadrinoTestApp/GET user/login"
    ])
  end

  def test_regex_route
    get '/regexes'
    assert_equal 200, last_response.status
    assert_equal "with extra regexes please!", last_response.body

    assert_metrics_recorded([
      "Controller/Sinatra/PadrinoTestApp/GET regex.*",
      "Apdex/Sinatra/PadrinoTestApp/GET regex.*"
    ])
  end
end
