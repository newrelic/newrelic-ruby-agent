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

  newrelic_ignore /\/.+regex.*/
  get '/skip_regex' do request.path_info end
  get '/regex_seen' do request.path_info end

  newrelic_ignore_apdex '/no_apdex'
  get '/no_apdex' do request.path_info end
end

class SinatraIgnoreTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include ::NewRelic::Agent::Instrumentation::Sinatra

  def app
    SinatraIgnoreTestApp
  end

  def app_name
    app.to_s
  end

  def setup
    ::NewRelic::Agent.manual_start
    ::NewRelic::Agent.instance.stats_engine.reset_stats
  end

  def get(path, *_)
    super
    assert_equal 200, last_response.status
    assert_equal path, last_response.body
  end

  def test_seen_route
    get '/record'
    assert_metrics_recorded([
      "Controller/Sinatra/#{app_name}/GET record",
      "Apdex/Sinatra/#{app_name}/GET record"])
  end

  def test_ignores_exact_match
    get '/ignore'
    assert_metrics_not_recorded([
      "Controller/Sinatra/#{app_name}/GET ignore",
      "Apdex/Sinatra/#{app_name}/GET ignore"])
  end

  def test_ignores_by_splats
    get '/splattered'
    assert_metrics_not_recorded([
      "Controller/Sinatra/#{app_name}/GET by_pattern",
      "Apdex/Sinatra/#{app_name}/GET by_pattern"])
  end

  def test_ignores_can_be_declared_in_batches
    get '/v1'
    get '/v2'
    get '/v3'

    assert_metrics_not_recorded([
      "Controller/Sinatra/#{app_name}/GET v1",
      "Controller/Sinatra/#{app_name}/GET v2",
      "Apdex/Sinatra/#{app_name}/GET v1",
      "Apdex/Sinatra/#{app_name}/GET v2"])

    assert_metrics_recorded([
      "Controller/Sinatra/#{app_name}/GET v3",
      "Apdex/Sinatra/#{app_name}/GET v3"])
  end

  def test_seen_with_regex
    get '/regex_seen'
    assert_metrics_recorded([
      "Controller/Sinatra/#{app_name}/GET regex_seen",
      "Apdex/Sinatra/#{app_name}/GET regex_seen"])
  end

  def test_ignores_by_regex
    get '/skip_regex'
    assert_metrics_not_recorded([
      "Controller/Sinatra/#{app_name}/GET skip_regex",
      "Apdex/Sinatra/#{app_name}/GET skip_regex"])
  end

  def test_ignore_apdex
    get '/no_apdex'
    assert_metrics_recorded(["Controller/Sinatra/#{app_name}/GET no_apdex"])
    assert_metrics_not_recorded(["Apdex/Sinatra/#{app_name}/GET no_apdex"])
  end

end
