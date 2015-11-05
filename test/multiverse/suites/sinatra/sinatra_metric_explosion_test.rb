# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class SinatraTestApp < Sinatra::Base
  get '/hello/:name' do |name|
    name ||= 'world'
    "hello #{name}"
  end

  get '/another_controller' do
    "I'm another controller"
  end

  get '/slow_transaction' do
    sleep 2
    'that was slow'
  end

  get '/agent_shutdown' do
    NewRelic::Agent.shutdown
    'ok'
  end
end

class SinatraMetricExplosionTest < Minitest::Test
  include Rack::Test::Methods
  include ::NewRelic::Agent::Instrumentation::Sinatra

  include MultiverseHelpers

  setup_and_teardown_agent

  def app
    SinatraTestApp
  end

  def test_sinatra_returns_properly
    get '/hello/world'
    assert_equal 'hello world', last_response.body
  end

  def test_transaction_name_from_route
    get '/hello/world'

    segment = if last_request.env.key? 'sinatra.route'
      'GET /hello/:name'
    else
      'GET hello/([^/?#]+)'
    end
    assert_metrics_recorded([
      "Controller/Sinatra/SinatraTestApp/#{segment}",
      "Apdex/Sinatra/SinatraTestApp/#{segment}"
    ])
  end

  def test_transaction_name_from_path
    get '/wrong'
    assert_metrics_recorded([
      'Controller/Sinatra/SinatraTestApp/GET (unknown)',
      'Apdex/Sinatra/SinatraTestApp/GET (unknown)'
    ])
  end

  def test_transaction_name_does_not_explode
    get '/hello/my%20darling'
    get '/hello/my_honey'
    get '/hello/my.ragtime.gal'
    get '/hello/isitmeyourelookingfor?'
    get '/another_controller'

    metric_names = ::NewRelic::Agent.agent.stats_engine.to_h.keys.map(&:to_s)
    metric_names -= [
      'CPU/User Time',
      "Middleware/all",
      "WebFrontend/QueueTime",
      "WebFrontend/WebServer/all",
    ]

    name_beginnings_to_ignore = [
      "ApdexAll",
      "Supportability",
      "GC/Transaction",
      "Nested/Controller",
      "Middleware"
    ]
    metric_names.delete_if do|metric|
      name_beginnings_to_ignore.any? {|name| metric.start_with?(name)}
    end

    assert_equal 6, metric_names.size, "Explosion detected in: #{metric_names.inspect}"
  end

  def test_does_not_break_when_no_verb_matches
    post '/some/garbage'

    assert_metrics_recorded([
      'Controller/Sinatra/SinatraTestApp/POST (unknown)',
      'Apdex/Sinatra/SinatraTestApp/POST (unknown)'
    ])
  end
end
