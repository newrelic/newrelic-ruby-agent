# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Context
        module Propagation
          class TracePropagatorTest < Minitest::Test
            class FakePropError < StandardError; end

            def setup
              @propagator = OpenTelemetry::Context::Propagation::TracePropagator.new
            end

            def test_inject_calls_distributed_tracing_api
              fake_carrier = {}

              DistributedTracing.stub(:insert_distributed_trace_headers, ->(carrier) { raise FakePropError.new }) do
                assert_raises(FakePropError) { @propagator.inject(fake_carrier) }
              end
            end

            def test_extract_returns_context_with_standard_headers
              with_config(:account_id => '190', primary_application_id: '46954') do
                carrier = {
                  'traceparent' => '00-da8bc8cc6d062849b0efcf3c169afb5a-7d3efb1b173fecfa-00',
                  'tracestate' => '190@nr=0-0-1-46954-7d3efb1b173fecfa-e8b91a159289ff74-00-00.23456-1518469636035'
                }

                result = @propagator.extract(carrier)

                # it's difficult to access the spancontext information
                # from a context object. parsing the string will help us
                # check the values with fewer shenanigans
                context_string = result.instance_variable_get(:@entries).to_s

                assert_match(/trace_id=\"da8bc8cc6d062849b0efcf3c169afb5a"/, context_string, 'trace_id does not match')
                assert_match(/span_id=\"7d3efb1b173fecfa"/, context_string, "span_id doesn't match")
                assert_match(/trace_flags=\"00\"/, context_string, "trace_flags doesn't match")
                assert_match(/@transaction_id=\"e8b91a159289ff74\"/, context_string, "transaction_id doesn't match")
                assert_match(/@sampled=false/, context_string, "sampled doesn't match")
                assert_match(/@priority=0.23456/, context_string, "priority doesn't match")
                assert_match(/@timestamp=1518469636035/, context_string, "timestamp doesn't match")
                assert_match(/@parent_app_id=\"46954/, context_string, "parent_app_id doesn't match")
              end
            end

            def test_extract_with_empty_carrier_returns_context
              carrier = {}
              result = @propagator.extract(carrier)

              assert_instance_of(::OpenTelemetry::Context, result)
            end

            def test_extract_returns_context_when_trace_context_parse_returns_nil
              carrier = {'traceparent' => 'invalid-trace-parent'}
              context = ::OpenTelemetry::Context.current

              # Stub TraceContext.parse to return nil
              NewRelic::Agent::DistributedTracing::TraceContext.stub(:parse, nil) do
                result = @propagator.extract(carrier, context: context)

                assert_instance_of(::OpenTelemetry::Context, result)
                assert_equal(context, result, 'Should return the original context when trace_context is nil')
              end
            end

            def test_extract_does_not_log_error_when_trace_context_is_nil
              carrier = {'traceparent' => 'malformed-data'}
              result = nil

              NewRelic::Agent::DistributedTracing::TraceContext.stub(:parse, nil) do
                log = with_array_logger(:debug) do
                  result = @propagator.extract(carrier)
                end

                refute log.array.any? { |m| m.include?('Unable to extract context') }, 'Expected error to not be logged for nil context'
                assert_instance_of(::OpenTelemetry::Context, result)
              end
            end

            def test_extract_handles_rack_getter
              # This getter class is deprecated and may go away someday
              # The other getter class in the code is from a different library
              # If we want to test with it, we need to add opentelemetry-common to
              # the Envfile
              with_config(:account_id => '190', primary_application_id: '46954') do
                rack_carrier = {
                  'HTTP_TRACEPARENT' => '00-da8bc8cc6d062849b0efcf3c169afb5a-7d3efb1b173fecfa-01',
                  'HTTP_TRACESTATE' => '190@nr=0-0-1-46954-7d3efb1b173fecfa-e8b91a159289ff74-01-01.23456-1518469636035'
                }
                result = @propagator.extract(rack_carrier, getter: ::OpenTelemetry::Context::Propagation.rack_env_getter)

                # it's difficult to access the spancontext information
                # from a context object. parsing the string will help us
                # check the values with fewer shenanigans
                context_string = result.instance_variable_get(:@entries).to_s

                assert_match(/trace_id=\"da8bc8cc6d062849b0efcf3c169afb5a"/, context_string, 'trace_id does not match')
                assert_match(/span_id=\"7d3efb1b173fecfa"/, context_string, "span_id doesn't match")
                assert_match(/trace_flags=\"01\"/, context_string, "trace_flags doesn't match")
                assert_match(/@transaction_id=\"e8b91a159289ff74\"/, context_string, "transaction_id doesn't match")
                assert_match(/@sampled=true/, context_string, "sampled doesn't match")
                assert_match(/@priority=1.23456/, context_string, "priority doesn't match")
                assert_match(/@timestamp=1518469636035/, context_string, "timestamp doesn't match")
                assert_match(/@parent_app_id=\"46954/, context_string, "parent_app_id doesn't match")
              end
            end
          end
        end
      end
    end
  end
end
