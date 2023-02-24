# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'rack/test'
require 'fake_collector'
require './testing_app'
require 'new_relic/rack/agent_hooks'

class CrossApplicationTracingTest < Minitest::Test
  include MultiverseHelpers
  setup_and_teardown_agent(:'cross_application_tracer.enabled' => true,
    :'distributed_tracing.enabled' => false,
    :cross_process_id => "boo",
    :encoding_key => "\0",
    :trusted_account_ids => [1]) \
  do |collector|
    collector.stub('connect', {
      'agent_run_id' => 666,
      'transaction_name_rules' => [{"match_expression" => "ignored_transaction",
                                    "ignore" => true}]
    })
  end

  include Rack::Test::Methods

  def app
    Rack::Builder.app { run(TestingApp.new) }
  end

  def test_cross_app_doesnt_modify_without_header
    get('/')

    refute last_response.headers["X-NewRelic-App-Data"]
  end

  def test_cross_app_doesnt_modify_with_invalid_header
    get('/', nil, {'HTTP_X_NEWRELIC_ID' => Base64.encode64('otherjunk')})

    refute last_response.headers["X-NewRelic-App-Data"]
  end

  def test_cross_app_writes_out_information
    get('/', nil, {'HTTP_X_NEWRELIC_ID' => Base64.encode64('1#234')})

    refute_nil last_response.headers["X-NewRelic-App-Data"]
    assert_metrics_recorded(['ClientApplication/1#234/all'])
  end

  def test_cross_app_doesnt_modify_if_txn_is_ignored
    get('/', {'transaction_name' => 'ignored_transaction'}, {'HTTP_X_NEWRELIC_ID' => Base64.encode64('1#234')})

    refute last_response.headers["X-NewRelic-App-Data"]
  end

  def test_cross_app_error_attaches_process_id_to_intrinsics
    assert_raises(RuntimeError) do
      get('/', {'fail' => 'true'}, {'HTTP_X_NEWRELIC_ID' => Base64.encode64('1#234')})
    end

    assert_includes attributes_for(last_traced_error, :intrinsic), :client_cross_process_id
  end

  def test_grpc_headers_returns_nil_if_the_headers_object_is_nil
    assert_nil tracer.send(:grpc_headers?, nil)
  end

  def test_grpc_headrs_returns_nil_if_the_headers_object_class_is_nil
    headers = MiniTest::Mock.new
    headers.expect :class, nil

    assert_nil tracer.send(:grpc_headers?, headers)
    headers.verify
  end

  def test_grpc_headers_returns_nil_if_the_headers_object_class_name_is_nil
    klass = MiniTest::Mock.new
    klass.expect :name, nil
    headers = MiniTest::Mock.new
    headers.expect :class, klass

    assert_nil tracer.send(:grpc_headers?, headers)
    klass.verify
    headers.verify
  end

  def test_grpc_headers_returns_false_if_the_headers_object_class_name_does_not_include_grpc
    klass = MiniTest::Mock.new
    klass.expect :name, 'The::Old::Man::and::the::Sea'
    headers = MiniTest::Mock.new
    headers.expect :class, klass

    refute tracer.send(:grpc_headers?, headers)
    klass.verify
    headers.verify
  end

  def test_grpc_headers_returns_true_if_the_headers_object_class_name_does_include_grpc
    klass = MiniTest::Mock.new
    klass.expect :name, 'NewRelic::Agent::Instrumentation::GRPC::Client::RequestWrapper'
    headers = MiniTest::Mock.new
    headers.expect :class, klass

    assert tracer.send(:grpc_headers?, headers)
    klass.verify
    headers.verify
  end

  # quick memoized access to an instance of a class that includes the
  # CrossAppTracing module
  def tracer
    @tracer ||= NewRelic::Agent::Transaction::DistributedTracer.new(nil)
  end

  load_cross_agent_test("cat_map").each do |test_case|
    # We only can do test cases here that don't involve outgoing calls
    if !test_case["outboundRequests"]
      if test_case['inboundPayload']
        request_headers = {
          'HTTP_X_NEWRELIC_ID' => Base64.encode64('1#234'),
          'HTTP_X_NEWRELIC_TRANSACTION' => json_dump_and_encode(test_case['inboundPayload'])
        }
      else
        request_headers = {}
      end

      define_method("test_#{test_case['name']}") do
        txn_name_parts = test_case['transactionName'].split('/')
        txn_category = txn_name_parts[0..1].join('/')
        txn_name = txn_name_parts[2..-1].join('/')

        request_params = {
          'transaction_name' => txn_name,
          'transaction_category' => txn_category,
          'guid' => test_case['transactionGuid']
        }

        with_config('app_name' => test_case['appName'],
          :'cross_application_tracer.enabled' => true,
          :'distributed_tracing.enabled'      => false) do
          get '/', request_params, request_headers
        end

        event = get_last_analytics_event

        assert_event_attributes(
          event,
          test_case['name'],
          test_case['expectedIntrinsicFields'],
          test_case['nonExpectedIntrinsicFields']
        )
      end
    end
  end
end
