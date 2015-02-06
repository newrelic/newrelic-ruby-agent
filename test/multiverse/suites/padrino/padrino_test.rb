# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# Shhhh
Padrino::Logger::Config[:development][:stream] = :null

class PadrinoTestApp < Padrino::Application

  register Padrino::Rendering
  register Padrino::Helpers

  get '/user/login' do
    "please log in"
  end

  get(/\/regex.*/) do
    "with extra regex's please!"
  end
end

class PadrinoRoutesTest < Minitest::Test
  include Rack::Test::Methods

  def app
    PadrinoTestApp
  end

  include MultiverseHelpers

  setup_and_teardown_agent

  def test_basic_route
    get '/user/login'
    assert_equal 200, last_response.status
    assert_equal 'please log in', last_response.body

    assert_metrics_recorded([
        "Controller/Sinatra/PadrinoTestApp/GET user/login",
        "Apdex/Sinatra/PadrinoTestApp/GET user/login"])
  end

  def test_regex_route
    get '/regexes'
    assert_equal 200, last_response.status
    assert_equal "with extra regex's please!", last_response.body

    assert_metrics_recorded([
        "Controller/Sinatra/PadrinoTestApp/GET regex.*",
        "Apdex/Sinatra/PadrinoTestApp/GET regex.*"])
  end
end
