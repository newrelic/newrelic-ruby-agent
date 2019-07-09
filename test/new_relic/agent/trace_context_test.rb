# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path '../../../test_helper', __FILE__
require 'new_relic/agent/trace_context'
require 'new_relic/agent/distributed_trace_payload'

module NewRelic
  module Agent
    class TraceContextTest < Minitest::Test

      def setup
        @config = {
          :account_id => "190",
          :primary_application_id => "46954",
          :disable_harvest_thread => true
        }

        NewRelic::Agent.config.add_config_for_testing(@config)
      end

      def teardown
        NewRelic::Agent.config.remove_config(@config)
        NewRelic::Agent.config.reset_to_defaults
      end

      def test_insert
        carrier = {}
        trace_id = 'a8e67265afe2773a3c611b94306ee5c2'
        parent_id = 'fb1010463ea28a38'
        trace_flags = 0x1
        trace_state = 'k1=asdf,k2=qwerty'

        TraceContext.insert format: TraceContext::HttpFormat,
                            carrier: carrier,
                            trace_id: trace_id,
                            parent_id: parent_id,
                            trace_flags: trace_flags,
                            trace_state: trace_state

        assert_equal "00-#{trace_id}-#{parent_id}-01", carrier['traceparent']
        assert_equal trace_state, carrier['tracestate']
      end

      def test_parse
        payload = make_payload

        carrier = {
          'traceparent' => '00-a8e67265afe2773a3c611b94306ee5c2-fb1010463ea28a38-01',
          'tracestate'  => "t5a@nr=#{payload.http_safe},other=asdf"
        }

        tracecontext_data = TraceContext.parse format: TraceContext::HttpFormat,
                                               carrier: carrier,
                                               tracestate_entry_key: "t5a@nr"

        traceparent = tracecontext_data.traceparent

        assert_equal '00', traceparent['version']
        assert_equal 'a8e67265afe2773a3c611b94306ee5c2', traceparent['trace_id']
        assert_equal 'fb1010463ea28a38', traceparent['parent_id']
        assert_equal '01', traceparent['trace_flags']

        assert_nil tracecontext_data.tenant_id
        assert_equal payload.text, tracecontext_data.tracestate_entry.text
        assert_equal ['other=asdf'], tracecontext_data.tracestate
      end

      def test_parse_with_nr_at_end
        payload = make_payload

        carrier = {
          'traceparent' => '00-a8e67265afe2773a3c611b94306ee5c2-fb1010463ea28a38-01',
          'tracestate'  => "other=asdf,t5a@nr=#{payload.http_safe}"
        }

        tracecontext_data = TraceContext.parse format: TraceContext::HttpFormat,
                                               carrier: carrier,
                                               tracestate_entry_key: "t5a@nr"

        traceparent = tracecontext_data.traceparent

        assert_equal '00', traceparent['version']
        assert_equal 'a8e67265afe2773a3c611b94306ee5c2', traceparent['trace_id']
        assert_equal 'fb1010463ea28a38', traceparent['parent_id']
        assert_equal '01', traceparent['trace_flags']

        assert_nil tracecontext_data.tenant_id
        assert_equal payload.text, tracecontext_data.tracestate_entry.text
        assert_equal ['other=asdf'], tracecontext_data.tracestate
      end

      def test_parse_with_nr_middle
        payload = make_payload

        carrier = {
          'traceparent' => '00-a8e67265afe2773a3c611b94306ee5c2-fb1010463ea28a38-01',
          'tracestate'  => "other=asdf,t5a@nr=#{payload.http_safe},otherother=asdfasdf"
        }

        tracecontext_data = TraceContext.parse format: TraceContext::HttpFormat,
                                               carrier: carrier,
                                               tracestate_entry_key: "t5a@nr"

        traceparent = tracecontext_data.traceparent

        assert_equal '00', traceparent['version']
        assert_equal 'a8e67265afe2773a3c611b94306ee5c2', traceparent['trace_id']
        assert_equal 'fb1010463ea28a38', traceparent['parent_id']
        assert_equal '01', traceparent['trace_flags']

        assert_nil tracecontext_data.tenant_id
        assert_equal payload.text, tracecontext_data.tracestate_entry.text
        assert_equal ['other=asdf','otherother=asdfasdf'], tracecontext_data.tracestate
      end

      def test_parse_tracestate_no_other_entries
        payload = make_payload
        carrier = make_inbound_carrier({'tracestate' => "t5a@nr=#{payload.http_safe}"})
        tracecontext_data = TraceContext.parse format: TraceContext::HttpFormat,
                                               carrier: carrier,
                                               tracestate_entry_key: "t5a@nr"
        assert_equal payload.text, tracecontext_data.tracestate_entry.text
        assert_equal [], tracecontext_data.tracestate
      end

      def test_parse_tracestate_no_nr_entry
        carrier = make_inbound_carrier
        tracecontext_data = TraceContext.parse format: TraceContext::HttpFormat,
                                               carrier: carrier,
                                               tracestate_entry_key: "t5a@nr"
        assert_equal nil, tracecontext_data.tracestate_entry
        assert_equal ['other=asdf'], tracecontext_data.tracestate
      end

      def make_inbound_carrier options = {}
        {
          'traceparent' => '00-a8e67265afe2773a3c611b94306ee5c2-fb1010463ea28a38-01',
          'tracestate'  => "other=asdf"
        }.update(options)
      end

      def make_payload
        in_transaction "test_txn" do |txn|
          return DistributedTracePayload.for_transaction txn
        end
      end
    end
  end
end
