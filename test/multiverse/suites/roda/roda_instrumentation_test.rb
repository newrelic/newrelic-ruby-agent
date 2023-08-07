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

class RodaInstrumentationTest < Minitest::Test
  include Rack::Test::Methods
  include MultiverseHelpers

  setup_and_teardown_agent

  def app
    RodaTestApp
  end

  def test_nil_verb
    NewRelic::Agent::Instrumentation::Roda::TransactionNamer.stub(:http_verb, nil) do
      get('/home')
      txn = harvest_transaction_events![1][0]

      assert_equal 'Controller/Roda/RodaTestApp/home', txn[0]['name']
      assert_equal 200, txn[2][:'http.statusCode']
    end
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
      get('/home')
      txn = harvest_transaction_events![1][0]

      assert_equal 'Controller/Roda/RodaTestApp/GET home', txn[0]['name']
    end
  end

  def test_roda_instrumentation_works_if_middleware_disabled
    with_config(:disable_middleware_instrumentation => true) do
      get('/home')
      txn = harvest_transaction_events![1][0]

      assert_equal 'Controller/Roda/RodaTestApp/GET home', txn[0]['name']
    end
  end
end
