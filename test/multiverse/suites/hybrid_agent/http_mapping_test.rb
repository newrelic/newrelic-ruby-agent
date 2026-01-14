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

          # drawing from the HTTP span client.rb instrumentation
          # stable patch
          def test_client_kind_segment_translates_attributes
            # this tests the case:
            # - if a transaction is in progress
            # - we don't pass along parent data since we're using the in_span API
            # - attributes given at the beginning
            # - attributes added with the span.set_attribute method
            # - not actually end-to-end because we're not making a request, just copying attributes
            request_attrs = {
              'http.request.method' => 'GET',
              'url.scheme' => 'http',
              'url.path' => '/success',
              'url.full' => 'http://example.com',
              'server.address' => 'example.com',
              'server.port' => 777
            }

            transaction = in_transaction do |txn|
              txn.stubs(:sampled?).returns(true)

              @tracer.in_span('GET', attributes: request_attrs, kind: :client) do |span|
                # TODO: decide if the line below copied from the instrumentation should be in the test
                # OpenTelemetry.propagation.inject(req.headers)
                span.set_attribute('http.response.status_code', 200)
              end
            end

            # this isn't right -- we need what the NR name would be
            # example Node name: 'External/www.newrelic.com/search'
            # uses net.peer.name and possibly url.full, but abridged?
            # assert_equal segment.name, 'name'
            # assert.example tx.traceId, span.spanContext.trace_id
            # then end the span
            # check the duration is in milliseconds?
            # assert span_kind => client
            # assert HTTP method applied to correct NR attribute
            # assert URL applied to right NR attribute
            # assert hostname applied to correct attribute
            # assert port applied to correct attribute
            # check the metrics
            # scoped:
            # assert.equal(metrics['External/www.newrelic.com/http'].callCount, 1)
            # unscoped:
            #         ;[
            #   'External/all',
            #   'External/allWeb',
            #   'External/www.newrelic.com/all',
            #   'External/www.newrelic.com/http'
            # ].forEach((expectedMetric) => {
            #   assert.equal(unscopedMetrics[expectedMetric].callCount, 1)
            # })
            # do we need to harvest?
            segment = transaction.segments[1]
            assert_instance_of NewRelic::Agent::Transaction::ExternalRequestSegment, segment
            # TODO: What should the name be? Should it match our standards for all the other request segments, or be something unique?
            # this would match Node:
            # assert_equal 'External/example.com/success', segment.name
            # this matches NR instrumentation:
            assert_equal 'External/example.com/OTelClient/GET', segment.name
            assert_equal request_attrs['server.address'], segment.host

            spans = harvest_span_events!

            span = spans[1][0]

            # first hash is the span in general (intrinsics)
            # second hash are the custom attributes
            # # and because we call add_attributes on everything right now, the otel attributes argument gets passed into this bucket
            # third hash are the agent attributes
            # which seems to just be http.url?
            binding.irb
            # assert_equal request_attrs
          end
        end
      end
    end
  end
end

=begin

EXISTING NR EXTERNAL REQUEST SPANS

{"type":"Span", X
"traceId":"f546c3cc39f26eacb726ba417c20eb9f", X
"guid":"2cce23538455d92d", X
"transactionId":"e7e8c8d980ca641e", X
"priority":1.714063, X
X "timestamp":1768008653142,
X "duration":0.36554384231567383,
X "name":"External/humane.org/Net::HTTP/GET",
X "thread.id":640,
X "sampled":true,
X "parentId":"22ccde680096fae0",
X "component":"Net::HTTP",
X "http.method":"GET",
X "http.request.method":"GET",
**"http.statusCode":200,
X "category":"http",
X "span.kind":"client",
X "server.address":"humane.org",
X "server.port":443},
X {},
X {"http.url":"https://humane.org/"}],

=end