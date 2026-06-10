# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        class HttpMappingTest < Minitest::Test
          def setup
            @tracer = NewRelic::Agent::OpenTelemetry::Trace::Tracer.new('OTelClient')
            harvest_transaction_events!
            harvest_span_events!
          end

          def teardown
            mocha_teardown
          end

          def request_attrs_v_1_17
            {
              'http.method' => 'GET',
              'http.scheme' => 'https',
              'http.target' => '/sustainable-spuds',
              'http.url' => 'https://potatoes.com/sustainable-spuds',
              'net.peer.name' => 'potatoes.com',
              'net.peer.port' => 443
            }
          end

          def request_attrs_v_1_23
            {
              'http.request.method' => 'GET',
              'url.scheme' => 'https',
              'url.path' => '/sustainable-spuds',
              'url.full' => 'https://potatoes.com/sustainable-spuds',
              'server.address' => 'potatoes.com',
              'server.port' => 443
            }
          end

          def run_http_client_span(attrs, status_attr)
            # In the external_request_segment_tests, we see the
            # category for a transaction is set to controller
            # to get the allWeb metric. If no category is provided
            # the category will be Other.
            in_transaction(category: :web) do |txn|
              txn.stubs(:sampled?).returns(true)
              @tracer.in_span('GET', attributes: attrs.dup, kind: :client) do |span|
                span.set_attribute(status_attr, 200)
              end
            end
          end

          # Drawing from the HTTP.rb OTel Contrib client.rb instrumentation
          # Using the "old" patch, which uses approx. version 1.17 semconv
          def test_client_v_1_17_segment_properties
            transaction = run_http_client_span(request_attrs_v_1_17, 'http.status_code')

            segment = transaction.segments[1]

            assert_instance_of NewRelic::Agent::Transaction::ExternalRequestSegment, segment

            assert_equal 'External/potatoes.com/OTelClient/GET', segment.name
            assert_equal request_attrs_v_1_17['net.peer.name'], segment.host
          end

          def test_client_v_1_17_metrics
            run_http_client_span(request_attrs_v_1_17, 'http.status_code')

            assert_metrics_recorded([
              'External/all',
              'External/allWeb',
              'External/potatoes.com/all',
              'External/potatoes.com/OTelClient/GET'
            ])
          end

          def test_client_v_1_17_intrinsic_attributes
            run_http_client_span(request_attrs_v_1_17, 'http.status_code')

            spans = harvest_span_events!
            span = spans[1][0]
            intrinsics = span[0]

            assert_equal request_attrs_v_1_17['http.method'], intrinsics['http.method']
            assert_equal request_attrs_v_1_17['http.method'], intrinsics['http.request.method']
            assert_equal request_attrs_v_1_17['net.peer.name'], intrinsics['server.address']
            assert_equal request_attrs_v_1_17['net.peer.port'], intrinsics['server.port']
            assert_equal 200, intrinsics['http.statusCode']
          end

          def test_client_v_1_17_custom_attributes
            run_http_client_span(request_attrs_v_1_17, 'http.status_code')

            spans = harvest_span_events!
            span = spans[1][0]
            custom = span[1]

            assert_equal request_attrs_v_1_17['http.scheme'], custom['http.scheme']
            assert_equal request_attrs_v_1_17['http.target'], custom['http.target']
          end

          def test_client_v_1_17_agent_attributes
            run_http_client_span(request_attrs_v_1_17, 'http.status_code')

            spans = harvest_span_events!
            span = spans[1][0]
            agent = span[2]

            assert_equal request_attrs_v_1_17['http.url'], agent['http.url']
            assert_equal 1, agent['status.code']
            assert_equal 'OTelClient', agent['otel.scope.name']
          end

          # Drawing from the HTTP.rb OTel Contrib client.rb instrumentation
          # Using the "stable" patch, which uses approx. version 1.23 semconv
          def test_client_v_1_23_segment_properties
            transaction = run_http_client_span(request_attrs_v_1_23, 'http.response.status_code')

            segment = transaction.segments[1]

            assert_instance_of NewRelic::Agent::Transaction::ExternalRequestSegment, segment

            assert_equal 'External/potatoes.com/OTelClient/GET', segment.name
            assert_equal request_attrs_v_1_23['server.address'], segment.host
          end

          def test_client_v_1_23_metrics
            run_http_client_span(request_attrs_v_1_23, 'http.response.status_code')

            assert_metrics_recorded([
              'External/all',
              'External/allWeb',
              'External/potatoes.com/all',
              'External/potatoes.com/OTelClient/GET'
            ])
          end

          def test_client_v_1_23_intrinsic_attributes
            run_http_client_span(request_attrs_v_1_23, 'http.response.status_code')

            spans = harvest_span_events!
            span = spans[1][0]
            intrinsics = span[0]

            assert_equal request_attrs_v_1_23['http.request.method'], intrinsics['http.method']
            assert_equal request_attrs_v_1_23['http.request.method'], intrinsics['http.request.method']
            assert_equal request_attrs_v_1_23['server.address'], intrinsics['server.address']
            assert_equal request_attrs_v_1_23['server.port'], intrinsics['server.port']
            assert_equal 200, intrinsics['http.statusCode']
          end

          def test_client_v_1_23_custom_attributes
            run_http_client_span(request_attrs_v_1_23, 'http.response.status_code')

            spans = harvest_span_events!
            span = spans[1][0]
            custom = span[1]

            assert_equal request_attrs_v_1_23['url.scheme'], custom['url.scheme']
            assert_equal request_attrs_v_1_23['url.path'], custom['url.path']
          end

          def test_client_v_1_23_agent_attributes
            run_http_client_span(request_attrs_v_1_23, 'http.response.status_code')

            spans = harvest_span_events!
            span = spans[1][0]
            agent = span[2]

            assert_equal request_attrs_v_1_23['url.full'], agent['http.url']
            assert_equal 1, agent['status.code']
            assert_equal 'OTelClient', agent['otel.scope.name']
          end
        end
      end
    end
  end
end
