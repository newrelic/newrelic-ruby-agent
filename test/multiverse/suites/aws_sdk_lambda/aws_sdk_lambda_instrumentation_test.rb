# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'aws_sdk_monkeypatch'
require 'json'

class AwsSdkLambdaInstrumentationTest < Minitest::Test
  REGION = 'us-east-2'
  AWS_ACCOUNT_ID = '8675309'

  def setup
    Aws.config.update(stub_responses: true)
  end

  def test_invoke
    perform_invocation(:invoke, {status_code: 200})
  end

  def test_invoke_async
    perform_invocation(:invoke_async, {}, {invoke_args: StringIO.new('null')})
  end

  def test_invoke_with_response_stream
    perform_invocation(:invoke_with_response_stream, {status_code: 200}, {event_stream_handler: proc { |_stream| 'hi' }})
  end

  # When using aws-sdk-lambda to invoke a function via its alias, the
  # `:function_name` argument passed to the invocation method will be in the
  # format of "<function name>:<alias>". The agent doesn't need to treat this
  # format of input in any special way, as naming and AWS arn creation will
  # simply work as expected.
  def test_invoke_with_alias
    perform_invocation(:invoke, {status_code: 200}, {alias: 'Freeman'})
  end

  def test_client_call_raises_an_exception
    in_transaction do |txn|
      client = Aws::Lambda::Client.new(region: REGION)
      client.config.account_id = AWS_ACCOUNT_ID
      def client.process_response(*_args); raise 'kaboom'; end

      assert_raises(RuntimeError) { client.invoke(function_name: 'Invoke-Me-And-Explode') }
      noticed_error = lambda_segment(txn).noticed_error

      assert_equal 'kaboom', noticed_error.message
      assert_equal 'RuntimeError', noticed_error.exception_class_name
    end
  end

  def test_client_response_indicates_an_unhandled_function_error
    function_error = 'Unhandled'
    message = 'oh no'
    type = 'Function<RuntimeError>'
    backtrace = ["/var/task/lambda_function.rb:4:in `lambda_handler'",
      "/var/runtime/gems/aws_lambda_ric-3.0.0/lib/aws_lambda_ric/lambda_handler.rb:28:in `call_handler'",
      "/var/runtime/gems/aws_lambda_ric-3.0.0/lib/aws_lambda_ric.rb:88:in `run_user_code'",
      "/var/runtime/gems/aws_lambda_ric-3.0.0/lib/aws_lambda_ric.rb:66:in `start_runtime_loop'",
      "/var/runtime/gems/aws_lambda_ric-3.0.0/lib/aws_lambda_ric.rb:49:in `run'",
      "/var/runtime/gems/aws_lambda_ric-3.0.0/lib/aws_lambda_ric.rb:221:in `bootstrap_handler'",
      "/var/runtime/gems/aws_lambda_ric-3.0.0/lib/aws_lambda_ric.rb:203:in `start'",
      "/var/runtime/index.rb:4:in `<main>'"]
    payload = StringIO.new(JSON.generate({'errorMessage' => message, 'errorType' => type, 'stackTrace' => backtrace}))
    response = {status_code: 200, function_error: function_error, payload: payload}

    in_transaction do |txn|
      function_name = 'Invoke-At-Your-Own-Risk'
      client = Aws::Lambda::Client.new(region: REGION, stub_responses: {invoke: response})
      client.config.account_id = AWS_ACCOUNT_ID
      client.invoke(function_name: function_name)
      noticed_error = lambda_segment(txn).noticed_error

      assert_equal "[#{function_error}] #{type} - #{message}", noticed_error.message
      assert_equal backtrace, noticed_error.stack_trace
    end
  end

  private

  def perform_invocation(method, response = {}, extra_args = {})
    function_name = 'Half-Life'
    al = extra_args.delete(:alias)
    function_name = "#{function_name}:#{al}" if al

    with_config('cloud.aws.account_id': AWS_ACCOUNT_ID) do
      in_transaction do |txn|
        client = Aws::Lambda::Client.new(region: REGION, stub_responses: {method => response})
        client.config.account_id = AWS_ACCOUNT_ID

        client.send(method, {function_name: function_name}.merge(extra_args))

        segment = lambda_segment(txn)

        assert_equal("External/Lambda/#{method}/#{function_name}", segment.name)
        assert_equal("lambda.#{REGION}.amazonaws.com", segment.host)
        assert_equal(200, segment.http_status_code) unless method == :invoke_async
        assert_equal('aws_sdk_lambda', segment.library) # rubocop:disable Minitest/EmptyLineBeforeAssertionMethods
        assert_equal({'cloud.platform' => 'aws_lambda',
                      'cloud.region' => REGION,
                      'cloud.account.id' => AWS_ACCOUNT_ID,
                      'cloud.resource_id' => "arn:aws:lambda:#{REGION}:#{AWS_ACCOUNT_ID}:function:#{function_name}"},
          agent_attributes(segment))
      end
    end
  end

  def agent_attributes(segment)
    segment.attributes.instance_variable_get(:@agent_attributes)
  end

  def lambda_segment(txn)
    segments = txn.segments.select { |s| s.name != 'dummy' }

    assert_equal 1, segments.size, "Expected to find exactly 1 Lambda client segment, found #{segments.size}"

    segments.first
  end
end
