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

class SinatraErrorTracingTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include ::NewRelic::Agent::Instrumentation::Sinatra

  def app
    SinatraErrorTracingTestApp
  end

  def setup
    ::NewRelic::Agent.manual_start
    @error_collector = ::NewRelic::Agent.instance.error_collector

    assert(@error_collector.enabled?,
           'error collector should be enabled')
  end

  def test_traps_errors
    get '/will_boom'
    assert_equal 500, last_response.status
    assert_equal 'We are sorry', last_response.body

    assert_equal(1, @error_collector.errors.size)
  end
end
