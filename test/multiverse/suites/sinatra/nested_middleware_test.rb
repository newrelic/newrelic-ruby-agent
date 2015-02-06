# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class MiddlewareApp < Sinatra::Base
  get '/middle' do
    "From the middlewarez"
  end
end

class MainApp < Sinatra::Base
  use MiddlewareApp

  get '/main' do
    "mainly done"
  end
end

class NestedMiddlewareTest < Minitest::Test
  include Rack::Test::Methods
  include MultiverseHelpers

  def app
    MainApp
  end

  setup_and_teardown_agent

  def test_inner_transaction
    get '/main'
    assert_metrics_recorded(["Controller/Sinatra/MainApp/GET main"])
    assert_metrics_not_recorded(["Controller/Sinatra/MiddlewareApp/GET (unknown)"])
  end

  def test_outer_transaction
    get '/middle'
    assert_metrics_recorded(["Controller/Sinatra/MiddlewareApp/GET middle"])
  end
end
