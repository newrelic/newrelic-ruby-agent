# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../../lib/new_relic/agent/instrumentation/roda/instrumentation'
require_relative '../../../../lib/new_relic/agent/instrumentation/roda/roda_transaction_namer'

class RodaTestApp < Roda
  plugin :error_handler do |e|
    'Oh No!'
  end

  route do |r|
    # GET / request
    r.root do
      r.redirect('home')
    end

    r.on('home') do
      'home page'
    end

    # /hello branch
    r.on('hello') do
      # GET /hello/:name request
      r.get(':name') do |name|
        "Hello #{name}!"
      end
    end

    r.on('error') do
      raise 'boom'
    end
  end
end

class RodaNoMiddleware < Roda; end

class RodaInstrumentationTest < Minitest::Test
  include Rack::Test::Methods
  include MultiverseHelpers

  setup_and_teardown_agent

  def app
    RodaTestApp
  end

  def test_http_verb_request_no_request_method
    fake_request = Struct.new('FakeRequest', :path).new
    name = NewRelic::Agent::Instrumentation::Roda::TransactionNamer.transaction_name(fake_request)

    assert_equal ::NewRelic::Agent::UNKNOWN_METRIC, name
  end

  def test_request_is_recorded
    get('/home')
    txn = harvest_transaction_events![1][0]

    assert_equal 'Controller/Roda/RodaTestApp/GET home', txn[0]['name']
    assert_equal 200, txn[2][:'http.statusCode']
  end

  def test_500_response_status
    get('/error')
    errors = harvest_error_traces!
    txn = harvest_transaction_events!

    assert_equal 500, txn[1][0][2][:"http.statusCode"]
    assert_equal 'Oh No!', last_response.body
    assert_equal 1, errors.size
  end

  def test_404_response_status
    get('/nothing')
    errors = harvest_error_traces!
    txn = harvest_transaction_events!

    assert_equal 404, txn[1][0][2][:"http.statusCode"]
    assert_equal 0, errors.size
  end

  def test_empty_route_name_and_response_status
    get('')
    errors = harvest_error_traces!
    txn = harvest_transaction_events![1][0]

    assert_equal 'Controller/Roda/RodaTestApp/GET /', txn[0]['name']
    assert_equal 302, txn[2][:'http.statusCode']
  end

  def test_roda_auto_middleware_disabled
    with_config(:disable_roda_auto_middleware => true) do
      RodaNoMiddleware.build_rack_app_with_tracing {}

      assert_truthy NewRelic::Agent::Agent::config[:disable_roda_auto_middleware]
    end
  end

  def test_roda_instrumentation_works_if_middleware_disabled
    with_config(:disable_middleware_instrumentation => true) do
      get('/home')
      txn = harvest_transaction_events![1][0]

      assert_equal 'Controller/Roda/RodaTestApp/GET home', txn[0]['name']
    end
  end

  def test_roda_namer_removes_rogue_slashes
    get('/home//')
    txn = harvest_transaction_events![1][0]

    assert_equal 'Controller/Roda/RodaTestApp/GET home', txn[0]['name']
  end

  def test_transaction_name_error
    NewRelic::Agent.stub(:logger, NewRelic::Agent::MemoryLogger.new) do
      # pass in {} to produce an error, because {} doesn't support #path and
      # confirm that the desired error handling took place
      result = NewRelic::Agent::Instrumentation::Roda::TransactionNamer.transaction_name({})

      assert_equal NewRelic::Agent::UNKNOWN_METRIC, result
      assert_logged(/NoMethodError.*Error encountered trying to identify Roda transaction name/m)
    end
  end

  def test_rack_request_params_error
    NewRelic::Agent.stub(:logger, NewRelic::Agent::MemoryLogger.new) do
      # Unit-syle test calling rack_request_params directly. No Rack request exists,
      # so @_request.params should fail.
      app.rack_request_params

      assert_logged(/Failed to get params from Rack request./)
    end
  end

  def assert_logged(expected)
    # Example logger array:
    # [[:debug, ["NoMethodError : undefined method `path' for \
    # {}:Hash - Error encountered trying to identify Roda transaction name"], nil]]
    found = NewRelic::Agent.logger.messages.any? { |m| m[1][0].match?(expected) }

    assert(found, "Didn't see log message: '#{expected}'")
  end
end
