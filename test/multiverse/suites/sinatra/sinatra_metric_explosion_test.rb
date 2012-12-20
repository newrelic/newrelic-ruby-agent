
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

class SinatraMetricExplosionTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include ::NewRelic::Agent::Instrumentation::Sinatra

  def app
    SinatraTestApp
  end

  def setup

    # puts ::NewRelic::Agent.manual_start
    # puts ::NewRelic::Agent.agent.started?.inspect
    ::NewRelic::Agent.agent.stats_engine.clear_stats
  end

  def test_sinatra_returns_properly
    get '/hello/world'
    assert_equal 'hello world', last_response.body
  end

  def test_transaction_name_from_route
    get '/hello/world'
    metric_names = ::NewRelic::Agent.agent.stats_engine.stats_hash.keys.map{|k| k.name}
    assert metric_names.include?('Controller/Sinatra/SinatraTestApp/GET hello/([^/?#]+)')
    assert metric_names.include?('Apdex/Sinatra/SinatraTestApp/GET hello/([^/?#]+)')
  end

  def test_transaction_name_from_path
    get '/wrong'
    metric_names = ::NewRelic::Agent.agent.stats_engine.stats_hash.keys.map{|k| k.name}
    assert metric_names.include?('Controller/Sinatra/SinatraTestApp/GET (unknown)')
    assert metric_names.include?('Apdex/Sinatra/SinatraTestApp/GET (unknown)')
  end

  def test_transaction_name_does_not_explode
    get '/hello/my%20darling'
    get '/hello/my_honey'
    get '/hello/my.ragtime.gal'
    get '/hello/isitmeyourelookingfor?'
    get '/another_controller'

    metric_names = ::NewRelic::Agent.agent.stats_engine.stats_hash.keys.
      map{|k| k.name} - ['CPU/User Time', "Middleware/all", "WebFrontend/QueueTime", "WebFrontend/WebServer/all"]
    assert_equal 6, metric_names.size, "Explosion detected in: #{metric_names.inspect}"
  end

  def test_does_not_break_when_no_verb_matches
    assert_nothing_raised do
      post '/some/garbage'
    end
    metric_names = ::NewRelic::Agent.agent.stats_engine.stats_hash.keys.map{|k| k.name}
    assert metric_names.include?('Controller/Sinatra/SinatraTestApp/POST (unknown)')
    assert metric_names.include?('Apdex/Sinatra/SinatraTestApp/POST (unknown)')
  end
end
