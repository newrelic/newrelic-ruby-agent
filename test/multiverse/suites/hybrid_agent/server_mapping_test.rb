# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        class ServerMappingTest < Minitest::Test
          def setup
            @tracer = NewRelic::Agent::OpenTelemetry::Trace::Tracer.new('OTelClient')
            harvest_transaction_events!
            harvest_span_events!
          end

          def teardown
            mocha_teardown
          end

          # The Agent Spec for attribute translation has specific version
          # numbers it uses. Ruby's semantic conventions for HTTP don't exactly
          # align with those versions.
          # Our agent will instead translate the "old" and "stable" semconv
          # versions used by the OTEL_SEMCONV_STABILITY_OPT_IN environment
          # variable.
          #
          # These attributes match what appear in a Rack request using old semconv
          def old_name
            'HTTP GET'
          end

          def old_req_attrs
            {
              'http.method' => 'GET',
              'http.host' => 'potatoes.com',
              'http.scheme' => 'http',
              'http.target' => '/sustainable-spuds',
              'http.user_agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36'
            }
          end

          def old_res_attrs
            {
              'http.status_code' => 418
            }
          end

          # These attributes match what appear in a Rack request using stable semconv
          def stable_name
            'GET'
          end

          def stable_req_attrs
            {
              'http.request.method' => 'GET',
              'server.address' => 'potatoes.com',
              'url.scheme' => 'http',
              'url.path' => '/sustainable-spuds',
              'url.query' => 'query=true',
              'user_agent.original' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36'
            }
          end

          def stable_res_attrs
            {
              'http.response.status_code' => 418
            }
          end

          # This roughly mimics the calls made by opentelemetry rack
          # instrumentation, but we ignore headers
          def run_server_transaction(name, request_attrs, response_attrs)
            span = @tracer.start_span(name, attributes: request_attrs.dup, kind: :server)
            span.finishable.stubs(:sampled?).returns(true)
            span.add_attributes(response_attrs)
            span.finish
          end

          def test_server_old_transaction_name
            run_server_transaction(old_name, old_req_attrs, old_res_attrs)

            txns = harvest_transaction_events!
            txn = txns[1][0]
            intrinsics = txn[0]

            assert_equal 'Controller/OTelClient/GET /sustainable-spuds', intrinsics['name']
          end

          def test_server_old_transaction_metrics
            run_server_transaction(old_name, old_req_attrs, old_res_attrs)

            assert_metrics_recorded([
              'HttpDispatcher',
              'Controller/OTelClient/GET /sustainable-spuds',
              'WebTransactionTotalTime',
              'WebTransactionTotalTime/Controller/OTelClient/GET /sustainable-spuds'
            ])
          end

          def test_server_old_transaction_agent_attributes
            attrs = old_req_attrs
            run_server_transaction(old_name, attrs, old_res_attrs)

            txns = harvest_transaction_events!
            txn = txns[1][0]
            agent = txn[2]

            assert_equal attrs['http.target'], agent['request.uri']
            assert_equal attrs['http.host'], agent['request.headers.host']
            assert_equal attrs['http.user_agent'], agent['request.headers.userAgent']
            assert_equal attrs['http.method'], agent['request.method']
            # we assign the status code as an instance variable rather than a
            # direct agent attribute, the key is a symbolized string
            assert_equal 418, agent[:'http.statusCode']
          end

          def test_server_old_span_custom_attributes
            attrs = old_req_attrs
            run_server_transaction(old_name, attrs, old_res_attrs)

            spans = harvest_span_events!
            span = spans[1][0]
            custom = span[1]

            keys_assigned_elsewhere = %w[http.method http.host http.user_agent http.target http.status_code]

            assert_empty custom.keys & keys_assigned_elsewhere
            assert_equal attrs['http.scheme'], custom['http.scheme']
          end

          def test_server_stable_transaction_name
            run_server_transaction(stable_name, stable_req_attrs, stable_res_attrs)

            txns = harvest_transaction_events!
            txn = txns[1][0]
            intrinsics = txn[0]

            assert_equal 'Controller/OTelClient/GET /sustainable-spuds', intrinsics['name']
          end

          def test_server_stable_transaction_metrics
            run_server_transaction(stable_name, stable_req_attrs, stable_res_attrs)

            assert_metrics_recorded([
              'HttpDispatcher',
              'Controller/OTelClient/GET /sustainable-spuds',
              'WebTransactionTotalTime',
              'WebTransactionTotalTime/Controller/OTelClient/GET /sustainable-spuds'
            ])
          end

          def test_server_stable_transaction_agent_attributes
            attrs = stable_req_attrs
            run_server_transaction(stable_name, attrs, stable_res_attrs)

            txns = harvest_transaction_events!
            txn = txns[1][0]
            agent = txn[2]

            # we assign the status code as an instance variable rather than a
            # direct agent attribute, the key is a symbolized string
            assert_equal 418, agent[:'http.statusCode']
            assert_equal attrs['url.path'], agent['request.uri']
            assert_equal attrs['server.address'], agent['request.headers.host']
            assert_equal attrs['user_agent.original'], agent['request.headers.userAgent']
            assert_equal attrs['http.request.method'], agent['request.method']
          end

          def test_server_stable_span_custom_attributes
            attrs = stable_req_attrs
            run_server_transaction(stable_name, attrs, stable_res_attrs)

            spans = harvest_span_events!
            span = spans[1][0]
            custom = span[1]

            keys_assigned_elsewhere = %w[http.request.method server.address url.path user_agent.original http.response.status_code]

            assert_empty custom.keys & keys_assigned_elsewhere
            assert_equal attrs['url.query'], custom['url.query']
          end
        end
      end
    end
  end
end
