# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

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
    end
  end
end
