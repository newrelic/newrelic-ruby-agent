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
          end

          def teardown
            mocha_teardown
            NewRelic::Agent.instance.transaction_event_aggregator.reset!
            NewRelic::Agent.instance.span_event_aggregator.reset!
          end

          # Drawing from the HTTP.rb OTel Contrib client.rb instrumentation
          # Using the "old" patch, which uses approx. version 1.17 semconv
          def test_client_kind_segment_translates_attributes_v_1_17
            request_attrs = {
              'http.method' => 'GET',
              'http.scheme' => 'https',
              'http.target' => '/sustainable-spuds',
              'http.url' => 'https://potatoes.com/sustainable-spuds',
              'net.peer.name' => 'potatoes.com',
              'net.peer.port' => 443
            }

            # In the external_request_segment_tests, we see the
            # category for a transaction is set to controller
            # to get the allWeb metric. If no category is provided
            # the category will be Other.
            transaction = in_transaction(category: :web) do |txn|
              txn.stubs(:sampled?).returns(true)

              @tracer.in_span('GET', attributes: request_attrs.dup, kind: :client) do |span|
                span.set_attribute('http.status_code', 200)
              end
            end

            segment = transaction.segments[1]

            assert_instance_of NewRelic::Agent::Transaction::ExternalRequestSegment, segment

            assert_equal 'External/potatoes.com/OTelClient/GET', segment.name
            assert_equal request_attrs['net.peer.name'], segment.host

            assert_metrics_recorded([
              'External/all',
              'External/allWeb',
              'External/potatoes.com/all',
              'External/potatoes.com/OTelClient/GET'
            ])

            spans = harvest_span_events!
            span = spans[1][0]
            intrinsics = span[0]
            custom = span[1]
            agent = span[2]

            assert_equal request_attrs['http.method'], intrinsics['http.method']
            assert_equal 200, intrinsics['http.statusCode']
            assert_equal request_attrs['net.peer.name'], intrinsics['server.address']
            assert_equal request_attrs['net.peer.port'], intrinsics['server.port']
            assert_equal request_attrs['http.scheme'], custom['http.scheme']
            assert_equal request_attrs['http.target'], custom['http.target']
            assert_equal request_attrs['http.url'], agent['http.url']
          end

          # Drawing from the HTTP.rb OTel Contrib client.rb instrumentation
          # Using the "stable" patch, which uses approx. version 1.23 semconv
          def test_client_kind_segment_translates_attributes_from_http_example_span_v_1_23
            request_attrs = {
              'http.request.method' => 'GET',
              'url.scheme' => 'https',
              'url.path' => '/sustainable-spuds',
              'url.full' => 'https://potatoes.com/sustainable-spuds',
              'server.address' => 'potatoes.com',
              'server.port' => 443
            }

            # In the external_request_segment_tests, we see the
            # category for a transaction is set to controller
            # to get the allWeb metric. If no category is provided
            # the category will be Other.
            transaction = in_transaction(category: :web) do |txn|
              txn.stubs(:sampled?).returns(true)

              @tracer.in_span('GET', attributes: request_attrs.dup, kind: :client) do |span|
                span.set_attribute('http.response.status_code', 200)
              end
            end

            segment = transaction.segments[1]

            assert_instance_of NewRelic::Agent::Transaction::ExternalRequestSegment, segment

            assert_equal 'External/potatoes.com/OTelClient/GET', segment.name
            assert_equal request_attrs['server.address'], segment.host

            assert_metrics_recorded([
              'External/all',
              'External/allWeb',
              'External/potatoes.com/all',
              'External/potatoes.com/OTelClient/GET'
            ])

            spans = harvest_span_events!
            span = spans[1][0]
            intrinsics = span[0]
            custom = span[1]
            agent = span[2]

            assert_equal request_attrs['http.request.method'], intrinsics['http.method']
            assert_equal 200, intrinsics['http.statusCode']
            assert_equal request_attrs['server.address'], intrinsics['server.address']
            assert_equal request_attrs['server.port'], intrinsics['server.port']
            assert_equal request_attrs['url.scheme'], custom['url.scheme']
            assert_equal request_attrs['url.path'], custom['url.path']
            assert_equal request_attrs['url.full'], agent['http.url']
          end
        end
      end
    end
  end
end
