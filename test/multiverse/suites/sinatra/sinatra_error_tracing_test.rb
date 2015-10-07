# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class SinatraErrorTracingTestApp < Sinatra::Base
  configure do
    set :show_exceptions, false
  end

  get '/will_boom' do
    raise 'Boom!'
  end

  error do
    'We are sorry'
  end
end

class SinatraErrorTracingTest < Minitest::Test
  include Rack::Test::Methods
  include ::NewRelic::Agent::Instrumentation::Sinatra

  include MultiverseHelpers

  setup_and_teardown_agent

  def app
    SinatraErrorTracingTestApp
  end

  def test_traps_errors
    get '/will_boom'
    assert_equal 500, last_response.status
    assert_equal 'We are sorry', last_response.body

    errors = harvest_error_traces!
    assert_equal(1, errors.size)
  end

  def test_ignores_notfound_errors_by_default
    get '/ignored_boom'
    assert_equal 404, last_response.status
    assert_match %r{Sinatra doesn&rsquo;t know this ditty\.}, last_response.body

    errors = harvest_error_traces!
    assert_equal(0, errors.size)
  end
end
