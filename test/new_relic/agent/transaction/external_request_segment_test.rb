# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/transaction'
require 'new_relic/agent/transaction/external_request_segment'

module NewRelic::Agent
  class Transaction
    class ExternalRequestSegmentTest < Minitest::Test
      class RequestWrapper
        attr_reader :headers

        def initialize(headers = {})
          @headers = headers
        end

        def [](key)
          @headers[key]
        end

        def []=(key, value)
          @headers[key] = value
        end

        def host_from_header
          self['host']
        end

        def to_s
          headers.to_s # so logging request headers works as expected
        end
      end

      TRANSACTION_GUID = 'BEC1BC64675138B9'

      def setup
        @obfuscator = NewRelic::Agent::Obfuscator.new('jotorotoes')
        NewRelic::Agent.agent.stubs(:connected?).returns(true)

        NewRelic::Agent.instance.span_event_aggregator.stubs(:enabled?).returns(true)
        nr_freeze_process_time
      end

      def teardown
        reset_buffers_and_caches
      end

      def test_generates_expected_name
        segment = ExternalRequestSegment.new('Typhoeus', 'http://remotehost.com/blogs/index', 'GET')

        assert_equal 'External/remotehost.com/Typhoeus/GET', segment.name
      end

      def test_downcases_hostname
        segment = ExternalRequestSegment.new('Typhoeus', 'http://ReMoTeHoSt.Com/blogs/index', 'GET')

        assert_equal 'External/remotehost.com/Typhoeus/GET', segment.name
      end

      def test_segment_does_not_record_metrics_outside_of_txn
        segment = ExternalRequestSegment.new('Net::HTTP', 'http://remotehost.com/blogs/index', 'GET')
        segment.finish

        refute_metrics_recorded [
          'External/remotehost.com/Net::HTTP/GET',
          'External/all',
          'External/remotehost.com/all',
          'External/allWeb',
          ['External/remotehost.com/Net::HTTP/GET', 'test']
        ]
      end

      def test_segment_records_expected_metrics
        in_transaction('test', :category => :controller) do
          segment = Tracer.start_external_request_segment(
            library: 'Net::HTTP',
            uri: 'http://remotehost.com/blogs/index',
            procedure: 'GET'
          )
          segment.finish
        end

        expected_metrics = [
          'External/remotehost.com/Net::HTTP/GET',
          'External/all',
          'External/remotehost.com/all',
          'External/allWeb',
          ['External/remotehost.com/Net::HTTP/GET', 'test']
        ]

        if Agent.config[:'distributed_tracing.enabled']
          expected_metrics << 'DurationByCaller/Unknown/Unknown/Unknown/Unknown/all'
          expected_metrics << 'DurationByCaller/Unknown/Unknown/Unknown/Unknown/allWeb'
        end

        assert_metrics_recorded expected_metrics
      end

      def test_segment_records_metrics_with_response_headers
        request = RequestWrapper.new
        response = {}

        in_transaction('test', :category => :controller) do
          segment = Tracer.start_external_request_segment(
            library: 'Net::HTTP',
            uri: 'http://remotehost.com/blogs/index',
            procedure: 'GET'
          )
          segment.add_request_headers(request)
          segment.process_response_headers(response)
          segment.finish
        end

        expected_metrics = [
          'External/remotehost.com/Net::HTTP/GET',
          'External/all',
          'External/remotehost.com/all',
          'External/allWeb',
          ['External/remotehost.com/Net::HTTP/GET', 'test'],
          'DurationByCaller/Unknown/Unknown/Unknown/Unknown/all',
          'DurationByCaller/Unknown/Unknown/Unknown/Unknown/allWeb'
        ]

        assert_metrics_recorded expected_metrics
      end

      def test_proper_metrics_recorded_for_distributed_trace_on_receiver
        with_config(:'distributed_tracing.enabled' => true,
          :trusted_account_key => 'trust_this!') do
          request = RequestWrapper.new
          payload = nil

          with_config(account_id: '190', primary_application_id: '46954') do
            in_transaction do |txn|
              payload = txn.distributed_tracer.create_distributed_trace_payload
            end
          end

          NewRelic::Agent.drop_buffered_data
          transport_type = nil

          in_transaction('test_txn2', :category => :controller) do |txn|
            txn.distributed_tracer.accept_distributed_trace_payload(payload.text)
            segment = Tracer.start_external_request_segment(
              library: 'Net::HTTP',
              uri: 'http://newrelic.com/blogs/index',
              procedure: 'GET'
            )
            transport_type = txn.distributed_tracer.caller_transport_type
            segment.add_request_headers(request)
            segment.finish
          end

          expected_metrics = [
            'External/all',
            'External/newrelic.com/all',
            'External/allWeb',
            "DurationByCaller/#{payload.parent_type}/#{payload.parent_account_id}/#{payload.parent_app_id}/#{transport_type}/all",
            "DurationByCaller/#{payload.parent_type}/#{payload.parent_account_id}/#{payload.parent_app_id}/#{transport_type}/allWeb",
            "TransportDuration/#{payload.parent_type}/#{payload.parent_account_id}/#{payload.parent_app_id}/#{transport_type}/all",
            "TransportDuration/#{payload.parent_type}/#{payload.parent_account_id}/#{payload.parent_app_id}/#{transport_type}/allWeb",
            ['External/newrelic.com/Net::HTTP/GET', 'test_txn2']
          ]

          assert_metrics_recorded expected_metrics
        end
      end

      def test_proper_metrics_recorded_for_distributed_trace_on_receiver_when_error_occurs
        with_config(
          :'distributed_tracing.enabled' => true,
          :trusted_account_key => 'trust_this'
        ) do
          request = RequestWrapper.new
          payload = nil

          with_config(account_id: '190', primary_application_id: '46954') do
            in_transaction do |txn|
              payload = txn.distributed_tracer.create_distributed_trace_payload
            end
          end

          NewRelic::Agent.drop_buffered_data
          transport_type = nil

          in_transaction('test_txn2', :category => :controller) do |txn|
            txn.distributed_tracer.accept_distributed_trace_payload(payload.text)
            segment = Tracer.start_external_request_segment(
              library: 'Net::HTTP',
              uri: 'http://newrelic.com/blogs/index',
              procedure: 'GET'
            )
            transport_type = txn.distributed_tracer.caller_transport_type
            segment.add_request_headers(request)
            segment.finish
            NewRelic::Agent.notice_error(StandardError.new('Sorry!'))
          end

          expected_metrics = [
            'External/all',
            'External/newrelic.com/all',
            'External/allWeb',
            "DurationByCaller/#{payload.parent_type}/#{payload.parent_account_id}/#{payload.parent_app_id}/#{transport_type}/all",
            "DurationByCaller/#{payload.parent_type}/#{payload.parent_account_id}/#{payload.parent_app_id}/#{transport_type}/allWeb",
            "TransportDuration/#{payload.parent_type}/#{payload.parent_account_id}/#{payload.parent_app_id}/#{transport_type}/all",
            "TransportDuration/#{payload.parent_type}/#{payload.parent_account_id}/#{payload.parent_app_id}/#{transport_type}/allWeb",
            "ErrorsByCaller/#{payload.parent_type}/#{payload.parent_account_id}/#{payload.parent_app_id}/#{transport_type}/all",
            "ErrorsByCaller/#{payload.parent_type}/#{payload.parent_account_id}/#{payload.parent_app_id}/#{transport_type}/allWeb",
            ['External/newrelic.com/Net::HTTP/GET', 'test_txn2']
          ]

          assert_metrics_recorded expected_metrics
        end
      end

      def test_segment_writes_outbound_request_headers_for_trace_context
        request = RequestWrapper.new
        with_config(trace_context_config) do
          in_transaction(:category => :controller) do
            segment = Tracer.start_external_request_segment(
              library: 'Net::HTTP',
              uri: 'http://remotehost.com/blogs/index',
              procedure: 'GET'
            )
            segment.add_request_headers(request)
            segment.finish
          end
        end

        assert request.headers.key?('traceparent'), 'Expected to find traceparent header'
        assert request.headers.key?('tracestate'), 'Expected to find tracestate header'
      end

      def test_add_request_headers_renames_segment_based_on_host_header
        request = RequestWrapper.new({'host' => 'anotherhost.local'})
        in_transaction(:category => :controller) do
          segment = Tracer.start_external_request_segment(
            library: 'Net::HTTP',
            uri: 'http://remotehost.com/blogs/index',
            procedure: 'GET'
          )

          assert_equal 'External/remotehost.com/Net::HTTP/GET', segment.name
          segment.add_request_headers(request)

          assert_equal 'External/anotherhost.local/Net::HTTP/GET', segment.name
          segment.finish
        end
      end

      # Can pass :status_code and any HTTP code in headers to alter
      # default 200 (OK) HTTP status code
      def with_external_segment(headers, config, segment_params)
        segment = nil
        http_response = nil
        with_config(config) do
          in_transaction(:category => :controller) do |txn|
            segment = Tracer.start_external_request_segment(**segment_params)
            segment.add_request_headers(headers)
            http_response = mock_http_response(headers)
            segment.process_response_headers(http_response)
            yield if block_given?
            segment.finish
          end
        end
        return [segment, http_response]
      end

      def test_sets_http_status_code_ok
        headers = {
          'status_code' => 200
        }
        segment_params = {
          library: 'Net::HTTP',
          uri: 'http://remotehost.com/blogs/index',
          procedure: 'GET'
        }
        segment, _http_response = with_external_segment(headers, {}, segment_params)

        assert_equal 200, segment.http_status_code
        refute_metrics_recorded 'External/remotehost.com/Net::HTTP/GET/Error'
      end

      def test_sets_http_status_code_not_found
        headers = {
          'status_code' => 404
        }

        segment_params = {
          library: 'Net::HTTP',
          uri: 'http://remotehost.com/blogs/index',
          procedure: 'GET'
        }
        segment, _http_response = with_external_segment(headers, {}, segment_params)

        assert_equal 404, segment.http_status_code
        refute_metrics_recorded 'External/remotehost.com/Net::HTTP/GET/MissingHTTPStatusCode'
      end

      def test_uri_recorded_as_tt_attribute
        segment = nil
        uri = 'http://newrelic.com/blogs/index'

        in_transaction(:category => :controller) do
          segment = Tracer.start_external_request_segment(
            library: 'Net::HTTP',
            uri: uri,
            procedure: 'GET'
          )
          segment.finish
        end

        sample = last_transaction_trace
        node = find_node_with_name(sample, segment.name)

        assert_equal uri, node.params[:uri]
      end

      def test_segment_adds_distributed_trace_header
        distributed_tracing_config = {
          :'distributed_tracing.enabled' => true,
          :account_id => '190',
          :primary_application_id => '46954'
        }

        with_config(distributed_tracing_config) do
          request = RequestWrapper.new
          with_config(distributed_tracing_config) do
            in_transaction(:category => :controller) do |txn|
              segment = Tracer.start_external_request_segment(
                library: 'Net::HTTP',
                uri: 'http://remotehost.com/blogs/index',
                procedure: 'GET'
              )
              segment.add_request_headers(request)
              segment.finish
            end
          end

          assert request.headers.key?('newrelic'), 'Expected to find newrelic header'
        end
      end

      def test_sets_start_time_from_api
        t = Process.clock_gettime(Process::CLOCK_REALTIME)

        in_transaction do |txn|
          segment = Tracer.start_external_request_segment(
            library: 'Net::HTTP',
            uri: 'http://remotehost.com/blogs/index',
            procedure: 'GET',
            start_time: t
          )
          segment.finish

          assert_equal t, segment.start_time
        end
      end

      def test_sampled_external_records_span_event
        with_config(distributed_tracing_config) do
          trace_id = nil
          txn_guid = nil
          sampled = nil
          priority = nil
          timestamp = nil
          segment = nil

          in_transaction('wat') do |txn|
            txn.stubs(:sampled?).returns(true)

            segment = ExternalRequestSegment.new('Typhoeus',
              'http://remotehost.com/blogs/index',
              'GET')
            txn.add_segment(segment)
            segment.start
            advance_process_time(1.0)
            segment.finish

            timestamp = Integer(segment.start_time * 1000.0)

            trace_id = txn.trace_id
            txn_guid = txn.guid
            sampled = txn.sampled?
            priority = txn.priority
          end

          last_span_events = NewRelic::Agent.agent.span_event_aggregator.harvest![1]

          assert_equal 2, last_span_events.size
          external_intrinsics, _, external_agent_attributes = last_span_events[0]
          root_span_event = last_span_events[1][0]
          root_guid = root_span_event['guid']

          expected_name = 'External/remotehost.com/Typhoeus/GET'

          assert_equal 'Span', external_intrinsics.fetch('type')
          assert_equal trace_id, external_intrinsics.fetch('traceId')
          refute_nil external_intrinsics.fetch('guid')
          assert_equal root_guid, external_intrinsics.fetch('parentId')
          assert_equal txn_guid, external_intrinsics.fetch('transactionId')
          assert_equal sampled, external_intrinsics.fetch('sampled')
          assert_equal priority, external_intrinsics.fetch('priority')
          assert_equal timestamp, external_intrinsics.fetch('timestamp')
          assert_in_delta(1.0, external_intrinsics.fetch('duration'))
          assert_equal expected_name, external_intrinsics.fetch('name')
          assert_equal segment.library, external_intrinsics.fetch('component')
          assert_equal segment.procedure, external_intrinsics.fetch('http.method')
          assert_equal segment.procedure, external_intrinsics.fetch('http.request.method')
          assert_equal 'remotehost.com', external_intrinsics.fetch('server.address')
          assert_equal 80, external_intrinsics.fetch('server.port')
          assert_equal 'http', external_intrinsics.fetch('category')
          assert_equal segment.uri.to_s, external_agent_attributes.fetch('http.url')
        end
      end

      def test_urls_are_filtered
        with_config(distributed_tracing_config) do
          segment = nil
          filtered_url = 'https://remotehost.com/bar/baz'

          in_transaction('wat') do |txn|
            txn.stubs(:sampled?).returns(true)

            segment = ExternalRequestSegment.new('Typhoeus',
              "#{filtered_url}?a=1&b=2#fragment",
              'GET')
            txn.add_segment(segment)
            segment.start
            advance_process_time(1.0)
            segment.finish
          end

          last_span_events = NewRelic::Agent.agent.span_event_aggregator.harvest![1]

          assert_equal 2, last_span_events.size
          _, _, external_agent_attributes = last_span_events[0]

          assert_equal filtered_url, segment.uri.to_s
          assert_equal filtered_url, external_agent_attributes.fetch('http.url')
        end
      end

      def test_non_sampled_segment_does_not_record_span_event
        in_transaction('wat') do |txn|
          txn.stubs(:sampled?).returns(false)

          segment = ExternalRequestSegment.new('Typhoeus',
            'http://remotehost.com/blogs/index',
            'GET')
          txn.add_segment(segment)
          segment.start
          advance_process_time(1.0)
          segment.finish
        end

        last_span_events = NewRelic::Agent.agent.span_event_aggregator.harvest![1]

        assert_empty last_span_events
      end

      def test_ignored_segment_does_not_record_span_event
        in_transaction('wat') do |txn|
          txn.stubs(:ignore?).returns(true)

          segment = ExternalRequestSegment.new('Typhoeus',
            'http://remotehost.com/blogs/index',
            'GET')
          txn.add_segment(segment)
          segment.start
          advance_process_time(1.0)
          segment.finish
        end

        last_span_events = NewRelic::Agent.agent.span_event_aggregator.harvest![1]

        assert_empty last_span_events
      end

      def test_span_event_truncates_long_value
        with_config(distributed_tracing_config) do
          in_transaction('wat') do |txn|
            txn.stubs(:sampled?).returns(true)
            segment = NewRelic::Agent::Tracer.start_external_request_segment( \
              library: 'Typhoeus',
              uri: "http://#{'a' * 300}.com",
              procedure: 'GET'
            )
            segment.finish
          end

          last_span_events = NewRelic::Agent.instance.span_event_aggregator.harvest![1]
          _, _, agent_attributes = last_span_events[0]

          assert_equal 255, agent_attributes['http.url'].bytesize
          assert_equal "http://#{'a' * 245}...", agent_attributes['http.url']
        end
      end

      def distributed_tracing_config
        {
          :'distributed_tracing.enabled' => true,
          :'span_events.enabled' => true
        }
      end

      def trace_context_config
        {
          :'distributed_tracing.enabled' => true,
          :account_id => '190',
          :primary_application_id => '46954',
          :trusted_account_key => 'trust_this!'
        }
      end

      def external_request_segment
        segment = NewRelic::Agent::Tracer.start_external_request_segment(
          library: :foo,
          uri: 'http://example.com/root/index',
          procedure: :get
        )
        v = yield(segment)
        segment.finish
        v
      end
    end
  end
end
