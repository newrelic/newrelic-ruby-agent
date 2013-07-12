# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'multiverse_helpers'

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

class SinatraErrorTracingTest < MiniTest::Unit::TestCase
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

    assert_equal(1, agent.error_collector.errors.size)
  end

  def test_ignores_notfound_errors_by_default
    get '/ignored_boom'
    assert_equal 404, last_response.status
    assert_match %r{Sinatra doesn&rsquo;t know this ditty\.}, last_response.body
    assert_equal(0, agent.error_collector.errors.size)
  end
end
