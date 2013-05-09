# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.join(File.dirname(__FILE__), '..', '..', '..', 'agent_helper.rb')

# Shhhh
Padrino::Logger::Config[:development][:stream] = :null

class PadrinoTestApp < Padrino::Application

  register Padrino::Rendering
  register Padrino::Helpers

  get '/user/login' do
    "please log in"
  end
end

class PadrinoRoutesTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    PadrinoTestApp
  end

  def setup
    ::NewRelic::Agent.manual_start
  end

  def test_lower_priority_route_conditions_arent_applied_to_higher_priority_routes
    get '/user/login'
    assert_equal 200, last_response.status
    assert_equal 'please log in', last_response.body

    assert_metrics_recorded([
        "Controller/Sinatra/PadrinoTestApp/GET user/login",
        "Apdex/Sinatra/PadrinoTestApp/GET user/login"])
  end
end
