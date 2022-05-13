# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../../test_helper'
require 'new_relic/agent/local_log_decorator'

module NewRelic::Agent
  module LocalLogDecorator
    class LocalLogDecoratorTest < Minitest::Test
      MESSAGE = 'message'.freeze
      METADATA_STRING = 'NR-LINKING|GUID|localhost|trace_id|span_id|app|'

      def setup
        @enabled_config = {
          :app_name => 'app',
          :entity_guid => 'GUID',
          :'application_logging.local_decorating.enabled' => true,
          :'application_logging.enabled' => true,
          :'instrumentation.logger' => 'auto'
        }
        NewRelic::Agent.config.add_config_for_testing(@enabled_config)
      end

      def teardown
        NewRelic::Agent.config.remove_config(@enabled_config)
      end

      def metadata_stubs
        NewRelic::Agent::Hostname.stubs(:get).returns('localhost')
        Tracer.stubs(:current_trace_id).returns('trace_id')
        Tracer.stubs(:current_span_id).returns('span_id')
      end

      def test_does_not_decorate_if_local_decoration_disabled
        with_config(
          :'application_logging.local_decorating.enabled' => false,
          :'application_logging.enabled' => true,
          :'instrumentation.logger' => 'disabled'
        ) do
          decorated_message = LocalLogDecorator.decorate(MESSAGE)
          assert_equal MESSAGE, decorated_message
        end
      end

      def test_does_not_decorate_if_instrumentation_logger_disabled
        with_config(
          :'instrumentation.logger' => 'disabled',
          :'application_logging.enabled' => true,
          :'application_logging.local_decorating.enabled' => true
        ) do
          decorated_message = LocalLogDecorator.decorate(MESSAGE)
          assert_equal MESSAGE, decorated_message
        end
      end

      def test_does_not_decorate_if_application_logging_disabled
        with_config(
          :'instrumentation.logger' => 'disabled',
          :'application_logging.enabled' => false,
          :'application_logging.local_decorating.enabled' => true
        ) do
          decorated_message = LocalLogDecorator.decorate(MESSAGE)
          assert_equal MESSAGE, decorated_message
        end
      end

      def test_decorates_if_enabled
        metadata_stubs
        decorated_message = LocalLogDecorator.decorate(MESSAGE)
        assert_equal decorated_message, "#{MESSAGE} #{METADATA_STRING}"
      end

      def test_decorate_puts_metadata_at_end_of_first_newline
        metadata_stubs
        message = "This is a test of the Emergency Alert System\n this is only a test...."
        decorated_message = LocalLogDecorator.decorate(message)
        assert_equal decorated_message, "This is a test of the Emergency Alert System #{METADATA_STRING}\n this is only a test...."
      end

      def test_URI_encodes_entity_name
        with_config(app_name: "My App | Production") do
          decorated_message = LocalLogDecorator.decorate(MESSAGE)
          assert_includes decorated_message, "My%20App%20%7C%20Production"
        end
      end

      def test_safe_without_entity_name
        with_config(app_name: nil) do
          decorated_message = LocalLogDecorator.decorate(MESSAGE)
          assert_includes decorated_message, '||'
        end
      end
    end
  end
end
