# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'json'
require 'logger'
require 'stringio'
require 'tempfile'
require 'zlib'

require_relative '../../test_helper'

# The customer's original lambda function that we wrap may live outside
# any namespace.
def customer_lambda_function(event:, context:)
  Logger.new(StringIO.new).info 'Lots of loggers languidly logging lore' if event.fetch(:simulate_logging, false)
  raise 'Kaboom!' if event.fetch(:simulate_exception, false)

  {statusCode: 200, body: 'Running just as fast as we can'}
end

# The customer's original lambda function may live within a namespace
module Willows
  class Wind
    def self.customer_lambda_function(event:, context:)
      {statusCode: 200, body: 'messing about in boats'}
    end
  end
end

# NOTE: additional integration style testing of the wrapping of the
# customer function is also conducted in the newrelic-lambda-layers repo.
module NewRelic::Agent
  class ServerlessHandler
    class ServerlessHandlerTest < Minitest::Test
      EVENT_SOURCES = JSON.parse(File.read(File.join(File.dirname(__FILE__), '..', '..', 'fixtures', 'cross_agent_tests', 'lambda', 'event_source_info.json')))

      AWS_TYPE_SPECIFIC_ATTRIBUTES = {
        's3' => {'aws.lambda.eventSource.bucketName' => 'example-bucket',
                 'aws.lambda.eventSource.eventName' => 'ObjectCreated:Put',
                 'aws.lambda.eventSource.eventTime' => '1970-01-01T00:00:00.000Z',
                 'aws.lambda.eventSource.length' => 1,
                 'aws.lambda.eventSource.objectKey' => 'test/key',
                 'aws.lambda.eventSource.objectSequencer' => '0A1B2C3D4E5F678901',
                 'aws.lambda.eventSource.objectSize' => 1024,
                 'aws.lambda.eventSource.region' => 'us-west-2'},
        'dynamo_streams' => {'aws.lambda.eventSource.length' => 3},
        'firehose' => {'aws.lambda.eventSource.length' => 1,
                       'aws.lambda.eventSource.region' => 'us-west-2'},
        'cloudFront' => {},
        'sqs' => {'aws.lambda.eventSource.length' => 1},
        'apiGateway' => {'aws.lambda.eventSource.accountId' => '123456789012',
                         'aws.lambda.eventSource.apiId' => '1234567890',
                         'aws.lambda.eventSource.resourceId' => '123456',
                         'aws.lambda.eventSource.resourcePath' => '/{proxy+}',
                         'aws.lambda.eventSource.stage' => 'prod'},
        'cloudWatch_scheduled' => {'aws.lambda.eventSource.account' => '{{{account-id}}}',
                                   'aws.lambda.eventSource.id' => 'cdc73f9d-aea9-11e3-9d5a-835b769c0d9c',
                                   'aws.lambda.eventSource.region' => 'us-west-2',
                                   'aws.lambda.eventSource.resource' => 'arn:aws:events:us-west-2:123456789012:rule/ExampleRule',
                                   'aws.lambda.eventSource.time' => '1970-01-01T00:00:00Z'},
        'ses' => {'aws.lambda.eventSource.date' => 'Wed, 7 Oct 2015 12:34:56 -0700',
                  'aws.lambda.eventSource.length' => 1,
                  'aws.lambda.eventSource.messageId' => '<0123456789example.com>',
                  'aws.lambda.eventSource.returnPath' => 'janedoe@example.com'},
        'sns' => {'aws.lambda.eventSource.length' => 1,
                  'aws.lambda.eventSource.messageId' => '95df01b4-ee98-5cb9-9903-4c221d41eb5e',
                  'aws.lambda.eventSource.timestamp' => '1970-01-01T00:00:00.000Z',
                  'aws.lambda.eventSource.topicArn' => 'arn:aws:sns:us-west-2:123456789012:ExampleTopic',
                  'aws.lambda.eventSource.type' => 'Notification'},
        'alb' => {},
        'kinesis' => {'aws.lambda.eventSource.length' => 1,
                      'aws.lambda.eventSource.region' => 'us-west-2'}
      }

      def setup
        config_hash = {:'serverless_mode.enabled' => true}
        @test_config = NewRelic::Agent::Configuration::DottedHash.new(config_hash, true)
        NewRelic::Agent.config.add_config_for_testing(@test_config, true)
        handler.send(:reset!)
      end

      def teardown
        NewRelic::Agent.config.remove_config(@test_config)
      end

      # integration style

      def test_the_complete_handoff_from_the_nr_lambda_layer
        context = testing_context
        output = with_output do
          result = handler.invoke_lambda_function_with_new_relic(method_name: :customer_lambda_function,
            event: {Opossum: :Virginia},
            context: context)

          assert_equal 'Running just as fast as we can', result[:body]
        end
        context.verify

        assert_equal 4, output.last['metric_data'].size
        assert_match(/lambda_function/, output.to_s)
      end

      def test_rescued_errors_are_noticed
        output = with_output do
          assert_raises RuntimeError do
            handler.invoke_lambda_function_with_new_relic(method_name: :customer_lambda_function,
              event: {simulate_exception: true},
              context: testing_context)
          end
        end

        errors = output.last['error_data'].last

        assert_equal 1, errors.size
        assert_equal 'lambda_function', errors.first[1]
        assert_equal 'Kaboom!', errors.first[2]
        assert_equal 'Kaboom!', output.last['error_event_data'].last.first.first['error.message']
      end

      def test_log_events_are_reported
        output = with_output do
          handler.invoke_lambda_function_with_new_relic(method_name: :customer_lambda_function,
            event: {simulate_logging: true},
            context: testing_context)
        end

        assert_match 'languidly', output.last['log_event_data'].first['logs'].first['message']
      end

      def test_customer_function_lives_within_a_namespace
        context = testing_context
        output = with_output do
          result = handler.invoke_lambda_function_with_new_relic(method_name: :customer_lambda_function,
            event: {Toad: :Hall},
            context: context,
            namespace: 'Willows::Wind')

          assert_equal 'messing about in boats', result[:body]
        end
        context.verify

        assert_equal 4, output.last['metric_data'].size
        assert_match(/lambda_function/, output.to_s)
      end

      def test_agent_attributes_are_present
        context = testing_context
        output = with_output do
          result = handler.invoke_lambda_function_with_new_relic(method_name: :customer_lambda_function,
            event: {},
            context: context)

          assert_equal 'Running just as fast as we can', result[:body]
        end
        context.verify
        agent_attributes_hash = output.last['analytic_event_data'].last.last.last

        assert agent_attributes_hash.key?('aws.lambda.arn')
        assert agent_attributes_hash.key?('aws.requestId')
      end

      def test_metric_data_adheres_to_the_agent_specs
        output = with_output do
          handler.invoke_lambda_function_with_new_relic(method_name: :customer_lambda_function,
            event: {},
            context: testing_context)
        end
        metric_data = output.last['metric_data']

        assert_kind_of Array, metric_data
        assert_equal 4, metric_data.size
        refute metric_data.first # agent run id
        assert_kind_of Float, metric_data[1] # start time
        assert_kind_of Float, metric_data[2] # stop time
        assert_kind_of Array, metric_data.last # array of metrics arrays
        refute metric_data.last.any? { |metric| metric.first.key?('scope') && metric.first['scope'].empty? },
          "Did not expect to find any metrics with a nil 'scope' value!"

        single_metric = metric_data.last.first

        assert_kind_of Array, single_metric
        assert_equal 2, single_metric.size
        assert_kind_of Hash, single_metric.first
        assert_kind_of Array, single_metric.last
        assert_equal 6, single_metric.last.size
      end

      def test_support_for_payload_format_v1
        NewRelic::Agent::ServerlessHandler.stub_const(:PAYLOAD_VERSION, 1) do
          output = with_output do
            result = handler.invoke_lambda_function_with_new_relic(method_name: :customer_lambda_function,
              event: {por_que_no: :los_dos},
              context: testing_context)

            assert_equal 'Running just as fast as we can', result[:body]
          end

          assert_equal 1, output.first, "Expected to find a payload version of '1', got #{output.first}"
          assert output.last.key?('metadata'), "Expected a v1 payload format with a 'metadata' key!"
          assert_equal 4, output.last['data']['metric_data'].size
          assert_match(/lambda_function/, output.to_s)
        end
      end

      def test_distributed_tracing_for_api_gateway_v1
        event = {'version' => '1.0',
                 'httpMethod' => 'POST',
                 'headers' => {NewRelic::NEWRELIC_KEY => {
                   NewRelic::TRACEPARENT_KEY => '00-a8e67265afe2773a3c611b94306ee5c2-fb1010463ea28a38-01',
                   NewRelic::TRACESTATE_KEY => '190@nr=0-0-190-2827902-7d3efb1b173fecfa-e8b91a159289ff74-1-1.23456-1518469636035'
                 }}}
        perform_distributed_tracing_based_invocation(event)
      end

      def test_distributed_tracing_for_api_gateway_v2
        event = {'version' => '2.0',
                 'httpMethod' => 'POST',
                 'requestContext' => {'http' => {NewRelic::NEWRELIC_KEY => {
                   NewRelic::TRACEPARENT_KEY => '00-a8e67265afe2773a3c611b94306ee5c2-fb1010463ea28a38-01',
                   NewRelic::TRACESTATE_KEY => '190@nr=0-0-190-2827902-7d3efb1b173fecfa-e8b91a159289ff74-1-1.23456-1518469636035'
                 }}}}
        perform_distributed_tracing_based_invocation(event)
      end

      def test_reports_web_attributes_for_api_gateway_v1
        event = {'version' => '1.0',
                 'resource' => '/RG35XXSP',
                 'path' => '/default/RG35XXSP',
                 'httpMethod' => 'POST',
                 'headers' => {'Content-Length' => '1138',
                               'Content-Type' => 'application/json',
                               'Host' => 'garbanz0.execute-api.us-west-1.amazonaws.com',
                               'User-Agent' => 'curl/8.4.0',
                               'X-Amzn-Trace-Id' => 'Root=1-08675309-3e0mfbschanamasala8302xv1',
                               'X-Forwarded-For' => '123.456.769.101',
                               'X-Forwarded-Port' => '443',
                               'X-Forwarded-Proto' => 'https',
                               'accept' => '*/*'},
                 'queryStringParameters' => {'param1': 'value1', 'param2': 'value2'},
                 'pathParameters' => nil,
                 'stageVariables' => nil,
                 'body' => '{"thekey1":"thevalue1"}',
                 'isBase64Encoded' => false}
        perform_http_attribute_based_invocation(event)
      end

      def test_reports_web_attributes_for_api_gateway_v2
        event = {'version' => '2.0',
                 'headers' => {'X-Forwarded-Port' => 443},
                 'queryStringParameters' => {'param1': 'value1', 'param2': 'value2'},
                 'requestContext' => {'http' => {'method' => 'POST',
                                                 'path' => '/default/RG35XXSP'},
                                      'domainName' => 'garbanz0.execute-api.us-west-1.amazonaws.com'}}
        perform_http_attribute_based_invocation(event)
      end

      EVENT_SOURCES.each do |type, info|
        define_method(:"test_event_type_#{type}") do
          skip 'This serverless test is limited to Ruby v3.2+' unless ruby_version_float >= 3.2

          output = with_output do
            handler.invoke_lambda_function_with_new_relic(method_name: :customer_lambda_function,
              event: info['event'],
              context: testing_context)
          end
          attributes = output.last['analytic_event_data'].last.last.last

          assert_equal info['expected_arn'], attributes['aws.lambda.eventSource.arn']
          assert_equal info['expected_type'], attributes['aws.lambda.eventSource.eventType']

          AWS_TYPE_SPECIFIC_ATTRIBUTES[type].each do |key, value|
            assert_equal value, attributes[key],
              "Expected agent attribute of '#{key}' with a value of '#{value}'. Got '#{attributes['key']}'"
          end
        end
      end

      # unit style

      def test_named_pipe_check_true
        skip_unless_minitest5_or_above

        File.stub :exist?, true, [NewRelic::Agent::ServerlessHandler::NAMED_PIPE] do
          File.stub :writable?, true, [NewRelic::Agent::ServerlessHandler::NAMED_PIPE] do
            assert_predicate handler, :use_named_pipe?
          end
        end
      end

      def test_named_pipe_check_false
        skip_unless_minitest5_or_above

        File.stub :exist?, false, [NewRelic::Agent::ServerlessHandler::NAMED_PIPE] do
          File.stub :writable?, false, [NewRelic::Agent::ServerlessHandler::NAMED_PIPE] do
            refute_predicate fresh_handler, :use_named_pipe?
          end
        end
      end

      def test_named_pipe_check_result_is_memoized
        skip_unless_minitest5_or_above

        h = fresh_handler
        # memoized to true when writable
        File.stub :exist?, true, [NewRelic::Agent::ServerlessHandler::NAMED_PIPE] do
          File.stub :writable?, true, [NewRelic::Agent::ServerlessHandler::NAMED_PIPE] do
            h.send(:use_named_pipe?)
          end
        end
        # memoization is used and fresh File checks are not performed
        File.stub :exist?, false, [NewRelic::Agent::ServerlessHandler::NAMED_PIPE] do
          File.stub :writable?, false, [NewRelic::Agent::ServerlessHandler::NAMED_PIPE] do
            assert_predicate h, :use_named_pipe?
          end
        end
      end

      def test_cold_is_true_only_for_the_first_check
        h = fresh_handler

        assert_predicate h, :cold?
        refute_predicate h, :cold?
        refute_predicate h, :cold?
      end

      def test_function_name_uses_env_var
        expected = 'The Zscaler ZIA chime is the worst sound in the world'
        ENV[NewRelic::Agent::ServerlessHandler::LAMBDA_ENVIRONMENT_VARIABLE] = expected

        assert_equal expected, handler.send(:function_name)
      ensure
        ENV.delete(NewRelic::Agent::ServerlessHandler::LAMBDA_ENVIRONMENT_VARIABLE)
      end

      def test_function_name_falls_back_on_a_default
        original_value = ENV[NewRelic::Agent::ServerlessHandler::LAMBDA_ENVIRONMENT_VARIABLE]
        ENV.delete(NewRelic::Agent::ServerlessHandler::LAMBDA_ENVIRONMENT_VARIABLE) if original_value

        assert_equal NewRelic::Agent::ServerlessHandler::FUNCTION_NAME, handler.send(:function_name)
      ensure
        ENV[NewRelic::Agent::ServerlessHandler::LAMBDA_ENVIRONMENT_VARIABLE] = original_value if original_value
      end

      def test_output_hits_stdout_in_the_absence_of_a_named_pipe
        h = fresh_handler
        def h.use_named_pipe?; false; end

        assert_output(/NR_LAMBDA_MONITORING/) do
          h.send(:write_output)
        end
      end

      def test_output_hits_the_named_pipe_when_available
        temp = Tempfile.new('lambda_named_pipe')

        NewRelic::Agent::ServerlessHandler.stub_const(:NAMED_PIPE, temp.path) do
          handler.instance_variable_set(:@context, testing_context)
          handler.send(:write_output)
        end

        output = File.read(temp).chomp

        assert_match(/NR_LAMBDA_MONITORING/, output)
      ensure
        temp.close
        temp.unlink
      end

      def test_store_payload
        method = :br_2049
        payload = 'little red bear'
        handler.store_payload(method, payload)

        assert_equal payload, handler.instance_variable_get(:@payloads)[method]
      end

      def test_store_payload_short_circuits_for_non_serverless_appropriate_methods
        blocked_method = NewRelic::Agent::ServerlessHandler::METHOD_BLOCKLIST.sample
        handler.store_payload(blocked_method, 'hoovering')

        assert_empty handler.instance_variable_get(:@payloads)
      end

      def test_agent_attributes_arent_set_without_a_transaction
        refute fresh_handler.send(:add_agent_attributes)
      end

      def test_custom_attributes_arent_supported_when_serverless
        skip_unless_minitest5_or_above

        attrs = {cool_id: 'James', server: 'less', current_time: Time.now.to_s}
        attribute_set_attempted = false
        tl_current_mock = Minitest::Mock.new
        tl_current_mock.expect :add_custom_attributes, -> { attribute_set_attempted = true }, [attrs]

        in_transaction do
          Transaction.stub :tl_current, tl_current_mock do
            ::NewRelic::Agent.add_custom_attributes(attrs)
          end
        end

        refute attribute_set_attempted
      end

      def test_metadata_for_payload_v1
        NewRelic::Agent::ServerlessHandler.stub_const(:PAYLOAD_VERSION, 1) do
          metadata = fresh_handler.send(:metadata)

          assert_kind_of Integer, metadata[:protocol_version]
          assert_nil metadata[:metadata_version]
          assert_nil metadata[:agent_language]
        end
      end

      def test_metadata_for_payload_v2
        metadata = fresh_handler.send(:metadata)

        assert_kind_of Integer, metadata[:protocol_version]
        assert_kind_of Integer, metadata[:metadata_version]
        refute_empty metadata[:agent_language]
      end

      private

      def handler
        NewRelic::Agent.agent.serverless_handler
      end

      def fresh_handler
        h = NewRelic::Agent::ServerlessHandler.new
        h.instance_variable_set(:@context, testing_context)
        h
      end

      def testing_context
        invoked_function_arn = 'Resident Alien'
        function_version = '1138'
        aws_request_id = 'microkelvin'
        context = Minitest::Mock.new
        context.expect :invoked_function_arn, invoked_function_arn
        context.expect :invoked_function_arn, invoked_function_arn
        context.expect :function_version, function_version
        context.expect :aws_request_id, aws_request_id
      end

      def with_output(&block)
        temp = Tempfile.new('lambda_named_pipe')
        NewRelic::Agent::ServerlessHandler.stub_const(:NAMED_PIPE, temp.path) do
          yield
        end
        json = File.read(temp).chomp
        array = JSON.parse(json)
        decoded = NewRelic::Base64.decode64(array.last)
        unzipped = Zlib::GzipReader.new(StringIO.new(decoded)).read
        array[-1] = JSON.parse(unzipped)
        array
      ensure
        temp.close
        temp.unlink
      end

      def distributed_tracing_config
        {
          :account_id => 190,
          :primary_application_id => '2827902',
          :trusted_account_key => 190,
          :'span_events.enabled' => true,
          :'distributed_tracing.enabled' => true
        }
      end

      def perform_distributed_tracing_based_invocation(event)
        output = nil
        with_config(distributed_tracing_config) do
          NewRelic::Agent.config.notify_server_source_added
          output = with_output do
            handler.invoke_lambda_function_with_new_relic(method_name: :customer_lambda_function,
              event: event,
              context: testing_context)
          end
        end
        success = output.last['metric_data'].last.detect do |metrics|
          metrics.first['name'] == 'Supportability/TraceContext/Accept/Success'
        end

        assert success, 'Failed to detect the supportability metric representing DT success'
      end

      def perform_http_attribute_based_invocation(event)
        output = with_output do
          NewRelic::Agent.instance.attribute_filter.stub(:allows_key?, true, ['http.url', AttributeFilter::DST_SPAN_EVENTS]) do
            handler.invoke_lambda_function_with_new_relic(method_name: :customer_lambda_function,
              event: event,
              context: testing_context)
          end
        end
        attrs = output.last['analytic_event_data'].last.last.last

        assert attrs, 'Unable to glean event attributes from the response output'
        assert_equal 'POST', attrs.fetch('http.method', nil)
        assert_equal 'POST', attrs.fetch('http.request.method', nil)
        assert_equal 200, attrs.fetch('http.statusCode', nil)
        assert_equal 'https://garbanz0.execute-api.us-west-1.amazonaws.com/default/RG35XXSP?param1=value1&param2=value2',
          attrs.fetch('http.url', nil)
      end
    end
  end
end
