# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

if NewRelic::Agent::Instrumentation::RackHelpers.version_supported? && defined? Rack

  require File.join(File.dirname(__FILE__), 'example_app')
  require 'new_relic/rack/browser_monitoring'
  require 'new_relic/rack/agent_hooks'

  class RackAutoInstrumentationTest < Minitest::Test
    include MultiverseHelpers

    setup_and_teardown_agent

    include Rack::Test::Methods

    def builder_class
      if defined? Puma::Rack::Builder
        Puma::Rack::Builder
      else
        Rack::Builder
      end
    end

    def app
      builder_class.app do
        use MiddlewareOne
        use MiddlewareTwo, 'the correct tag' do |headers|
          headers['MiddlewareTwoBlockTag'] = 'the block tag'
        end
        use MiddlewareThree, tag: 'the correct tag'
        use NewRelic::Rack::BrowserMonitoring
        use NewRelic::Rack::AgentHooks
        run ExampleApp.new
      end
    end

    def test_middleware_gets_used
      get '/'
      assert last_response.headers['MiddlewareOne']
      assert last_response.headers['MiddlewareTwo']
      assert last_response.headers['MiddlewareThree']
    end

    def test_status_code_is_preserved
      get '/'
      assert_equal 200, last_response.status
    end

    def test_header_is_preserved
      get '/'
      assert last_response.headers['ExampleApp']
    end

    def test_body_is_preserved
      get '/'
      assert_equal 'A barebones rack app.', last_response.body
    end

    def test_non_agent_middlewares_do_not_record_metrics_if_disabled_by_config
      with_config(:disable_middleware_instrumentation => true) do
        get '/'
      end

      assert_metrics_recorded_exclusive(
        [
          "Apdex",
          "ApdexAll",
          "HttpDispatcher",
          "Middleware/all",
          "Apdex/Middleware/Rack/NewRelic::Rack::AgentHooks/call",
          "Controller/Middleware/Rack/NewRelic::Rack::AgentHooks/call",
          "Middleware/Rack/NewRelic::Rack::BrowserMonitoring/call",
          "Middleware/Rack/NewRelic::Rack::AgentHooks/call",
          "WebTransactionTotalTime",
          "WebTransactionTotalTime/Controller/Middleware/Rack/NewRelic::Rack::AgentHooks/call",
          ["Middleware/Rack/NewRelic::Rack::AgentHooks/call", "Controller/Middleware/Rack/NewRelic::Rack::AgentHooks/call"],
          ["Middleware/Rack/NewRelic::Rack::BrowserMonitoring/call", "Controller/Middleware/Rack/NewRelic::Rack::AgentHooks/call"],
          'DurationByCaller/Unknown/Unknown/Unknown/HTTP/all',
          'Supportability/API/recording_web_transaction?',
          'DurationByCaller/Unknown/Unknown/Unknown/HTTP/allWeb'
        ],
        :ignore_filter => /^(Supportability|Logging)/
      )
    end

    def test_middlewares_record_metrics
      NewRelic::Agent.agent.stats_engine.reset!
      get '/'
      assert_metrics_recorded_exclusive(
        [
          "Apdex",
          "ApdexAll",
          "HttpDispatcher",
          "Middleware/all",
          "Apdex/Rack/ExampleApp/call",
          "Controller/Rack/ExampleApp/call",
          "Middleware/Rack/MiddlewareOne/call",
          "Middleware/Rack/MiddlewareTwo/call",
          "Middleware/Rack/MiddlewareThree/call",
          "Middleware/Rack/NewRelic::Rack::BrowserMonitoring/call",
          "Middleware/Rack/NewRelic::Rack::AgentHooks/call",
          "Nested/Controller/Rack/ExampleApp/call",
          "Supportability/API/browser_timing_header",
          "WebTransactionTotalTime",
          "WebTransactionTotalTime/Controller/Rack/ExampleApp/call",
          ["Middleware/Rack/NewRelic::Rack::BrowserMonitoring/call", "Controller/Rack/ExampleApp/call"],
          ["Middleware/Rack/NewRelic::Rack::AgentHooks/call", "Controller/Rack/ExampleApp/call"],
          ["Middleware/Rack/MiddlewareOne/call", "Controller/Rack/ExampleApp/call"],
          ["Middleware/Rack/MiddlewareTwo/call", "Controller/Rack/ExampleApp/call"],
          ["Middleware/Rack/MiddlewareThree/call", "Controller/Rack/ExampleApp/call"],
          ["Nested/Controller/Rack/ExampleApp/call", "Controller/Rack/ExampleApp/call"],
          'DurationByCaller/Unknown/Unknown/Unknown/HTTP/all',
          'Supportability/API/recording_web_transaction?',
          'DurationByCaller/Unknown/Unknown/Unknown/HTTP/allWeb'
        ],
        :ignore_filter => /^(Supportability|Logging)/
      )
    end

    def test_middlewares_record_queue_time
      t0 = nr_freeze_process_time
      advance_process_time(5.0)
      get '/', {}, {'HTTP_X_REQUEST_START' => "t=#{t0.to_f}"}

      assert_metrics_recorded(
        'WebFrontend/QueueTime' => {:total_call_time => 5.0}
      )
    end

    def test_middleware_that_returns_early_records_middleware_rollup_metric
      get '/?return-early=true'

      assert_metrics_recorded_exclusive(
        [
          "Apdex",
          "ApdexAll",
          "HttpDispatcher",
          "Middleware/all",
          "Apdex/Middleware/Rack/MiddlewareTwo/call",
          "Controller/Middleware/Rack/MiddlewareTwo/call",
          "Middleware/Rack/MiddlewareOne/call",
          "Middleware/Rack/MiddlewareTwo/call",
          "WebTransactionTotalTime",
          "WebTransactionTotalTime/Controller/Middleware/Rack/MiddlewareTwo/call",
          ["Middleware/Rack/MiddlewareOne/call", "Controller/Middleware/Rack/MiddlewareTwo/call"],
          ["Middleware/Rack/MiddlewareTwo/call", "Controller/Middleware/Rack/MiddlewareTwo/call"],
          'DurationByCaller/Unknown/Unknown/Unknown/HTTP/all',
          'DurationByCaller/Unknown/Unknown/Unknown/HTTP/allWeb'
        ],
        :ignore_filter => /^(Supportability|Logging)/
      )
    end

    def test_middleware_that_returns_early_middleware_all_has_correct_call_times
      nr_freeze_process_time
      get '/?return-early=true'
      assert_metrics_recorded('Middleware/all' => {:total_exclusive_time => 3.0, :call_count => 2})
    end

    def test_middleware_created_with_args_works
      get '/'

      assert_equal('the correct tag', last_response.headers['MiddlewareTwoTag'])
      assert_equal('the block tag', last_response.headers['MiddlewareTwoBlockTag'])
    end

    def test_middleware_created_with_kwargs_works
      get '/'

      assert_equal('the correct tag', last_response.headers['MiddlewareThreeTag'])
    end
  end

end
