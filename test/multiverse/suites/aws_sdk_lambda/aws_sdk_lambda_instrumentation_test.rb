# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'aws_sdk_monkeypatch'

class AwsSdkLambdaInstrumentationTest < Minitest::Test
  REGION = 'us-east-2'
  AWS_ACCOUNT_ID = '8675309'

  def setup
    Aws.config.update(stub_responses: true)
    @client = Aws::Lambda::Client.new(region: REGION)
    @client.config.account_id = AWS_ACCOUNT_ID
  end

  def test_invoke
    perform_invocation(:invoke)
  end

  def test_invoke_async
    perform_invocation(:invoke_async, invoke_args: StringIO.new('null'))
  end

  def test_invoke_with_response_stream
    perform_invocation(:invoke_with_response_stream, event_stream_handler: proc { |_stream| 'hi' })
  end

  # TODO
  def test_client_call_raises_an_exception
  end

  # TODO
  def test_client_response_indicates_an_unhandled_function_error
  end

  # TODO
  def test_client_response_indicates_a_handled_function_error
  end

  private

  def perform_invocation(method, extra_args = {})
    function_name = 'Half-Life'

    in_transaction do |txn|
      @client.send(method, {function_name: function_name}.merge(extra_args))

      segment = lambda_segment(txn)

      assert_equal("External/Lambda/#{method}/#{function_name}", segment.name)
      assert_equal("lambda.#{REGION}.amazonaws.com", segment.host)

      # TODO: `yield` returns `nil` under AWS SDK response stubbing, so the
      #        response status code, function error, and body won't work
      # assert_equal(200, segment.http_status_code) unless method == :invoke_async

      assert_equal('aws_sdk_lambda', segment.library)
      assert_equal({'cloud.platform' => 'aws_lambda',
                    'cloud.region' => REGION,
                    'cloud.account.id' => AWS_ACCOUNT_ID,
                    'cloud.resource_id' => "arn:aws:lambda:#{REGION}:#{AWS_ACCOUNT_ID}:function:#{function_name}"},
        agent_attributes(segment))
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



__END__


require 'json'

# 1.
client = Aws::Lambda::Client.new(region: 'us-east-2')
response = client.invoke(function_name: 'Half-Life')
JSON.parse(response.payload.string)

# 2.
response = client.invoke_async({function_name: 'Half-Life', invoke_args: "{}"})
response.status # => 202

# 3.
response = client.invoke_with_response_stream({function_name: 'Half-Life'}) { |str| }


resp = client.invoke({
  function_name: "NamespacedFunctionName", # required
  invocation_type: "Event", # accepts Event, RequestResponse, DryRun
  log_type: "None", # accepts None, Tail
  client_context: "String",
  payload: "data",
  qualifier: "Qualifier",
})

# Response structure

resp.status_code #=> Integer
resp.function_error #=> String
resp.log_result #=> String
resp.payload #=> String
resp.executed_version #=> String
