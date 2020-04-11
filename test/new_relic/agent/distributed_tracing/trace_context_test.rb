# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path '../../../../test_helper', __FILE__

module NewRelic::Agent::DistributedTracing
  class TraceContextTest < Minitest::Test

    def setup
      @config = {
        :account_id => "190",
        :primary_application_id => "46954",
        :disable_harvest_thread => true,
        :'distributed_tracing.enabled' => true
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

      TraceContext.insert format: NewRelic::FORMAT_NON_RACK,
                          carrier: carrier,
                          trace_id: trace_id,
                          parent_id: parent_id,
                          trace_flags: trace_flags,
                          trace_state: trace_state

      assert_equal "00-#{trace_id}-#{parent_id}-01", carrier['traceparent']
      assert_equal trace_state, carrier['tracestate']
    end

    def test_parse_format_non_rack
      payload = make_payload

      carrier = {
        NewRelic::TRACEPARENT_KEY => '00-a8e67265afe2773a3c611b94306ee5c2-fb1010463ea28a38-01',
        NewRelic::TRACESTATE_KEY  => "190@nr=#{payload.to_s},other=asdf"
      }

      trace_context_header_data = TraceContext.parse format: NewRelic::FORMAT_NON_RACK,
                                             carrier: carrier,
                                             trace_state_entry_key: "190@nr"

      trace_parent = trace_context_header_data.trace_parent

      assert_equal '00', trace_parent['version']
      assert_equal 'a8e67265afe2773a3c611b94306ee5c2', trace_parent['trace_id']
      assert_equal 'fb1010463ea28a38', trace_parent['parent_id']
      assert_equal '01', trace_parent['trace_flags']

      assert_equal payload.to_s, trace_context_header_data.trace_state_payload.to_s
      assert_equal 'new=entry,other=asdf', trace_context_header_data.trace_state('new=entry')
    end

    def test_parse_format_rack
      payload = make_payload

      carrier = {
        NewRelic::HTTP_TRACEPARENT_KEY => '00-a8e67265afe2773a3c611b94306ee5c2-fb1010463ea28a38-01',
        NewRelic::HTTP_TRACESTATE_KEY  => "190@nr=#{payload.to_s},other=asdf"
      }

      trace_context_header_data = TraceContext.parse format: NewRelic::FORMAT_RACK,
                                             carrier: carrier,
                                             trace_state_entry_key: "190@nr"

      trace_parent = trace_context_header_data.trace_parent

      assert_equal '00', trace_parent['version']
      assert_equal 'a8e67265afe2773a3c611b94306ee5c2', trace_parent['trace_id']
      assert_equal 'fb1010463ea28a38', trace_parent['parent_id']
      assert_equal '01', trace_parent['trace_flags']

      assert_equal payload.to_s, trace_context_header_data.trace_state_payload.to_s
      assert_equal 'new=entry,other=asdf', trace_context_header_data.trace_state('new=entry')
    end

    def test_parse_with_nr_at_end
      payload = make_payload

      carrier = {
        NewRelic::TRACEPARENT_KEY => '00-a8e67265afe2773a3c611b94306ee5c2-fb1010463ea28a38-01',
        NewRelic::TRACESTATE_KEY  => "other=asdf,190@nr=#{payload.to_s}"
      }

      trace_context_header_data = TraceContext.parse format: NewRelic::FORMAT_NON_RACK,
                                             carrier: carrier,
                                             trace_state_entry_key: "190@nr"

      trace_parent = trace_context_header_data.trace_parent

      assert_equal '00', trace_parent['version']
      assert_equal 'a8e67265afe2773a3c611b94306ee5c2', trace_parent['trace_id']
      assert_equal 'fb1010463ea28a38', trace_parent['parent_id']
      assert_equal '01', trace_parent['trace_flags']

      assert_equal payload.to_s, trace_context_header_data.trace_state_payload.to_s
      assert_equal 'new=entry,other=asdf', trace_context_header_data.trace_state('new=entry')
    end

    def test_parse_with_nr_middle
      payload = make_payload

      carrier = {
        NewRelic::TRACEPARENT_KEY => '00-a8e67265afe2773a3c611b94306ee5c2-fb1010463ea28a38-01',
        NewRelic::TRACESTATE_KEY  => "other=asdf,190@nr=#{payload.to_s},otherother=asdfasdf"
      }

      trace_context_header_data = TraceContext.parse format: NewRelic::FORMAT_NON_RACK,
                                             carrier: carrier,
                                             trace_state_entry_key: "190@nr"

      trace_parent = trace_context_header_data.trace_parent

      assert_equal '00', trace_parent['version']
      assert_equal 'a8e67265afe2773a3c611b94306ee5c2', trace_parent['trace_id']
      assert_equal 'fb1010463ea28a38', trace_parent['parent_id']
      assert_equal '01', trace_parent['trace_flags']

      assert_equal payload.to_s, trace_context_header_data.trace_state_payload.to_s
      assert_equal 'new=entry,other=asdf,otherother=asdfasdf', trace_context_header_data.trace_state('new=entry')
    end

    def test_parse_with_nr_middle_and_spaces
      payload = make_payload

      carrier = {
        NewRelic::TRACEPARENT_KEY => '00-a8e67265afe2773a3c611b94306ee5c2-fb1010463ea28a38-01',
        NewRelic::TRACESTATE_KEY  => "other=asdf , \t190@nr=#{payload.to_s},\totherother=asdfasdf"
      }

      trace_context_header_data = TraceContext.parse format: NewRelic::FORMAT_NON_RACK,
                                             carrier: carrier,
                                             trace_state_entry_key: "190@nr"

      trace_parent = trace_context_header_data.trace_parent

      assert_equal '00', trace_parent['version']
      assert_equal 'a8e67265afe2773a3c611b94306ee5c2', trace_parent['trace_id']
      assert_equal 'fb1010463ea28a38', trace_parent['parent_id']
      assert_equal '01', trace_parent['trace_flags']

      assert_equal payload.to_s, trace_context_header_data.trace_state_payload.to_s
      assert_equal 'new=entry,other=asdf,otherother=asdfasdf', trace_context_header_data.trace_state('new=entry')
    end

    def test_parse_tracestate_no_other_entries
      payload = make_payload
      carrier = make_inbound_carrier({'tracestate' => "190@nr=#{payload.to_s}"})
      trace_context_header_data = TraceContext.parse format: NewRelic::FORMAT_NON_RACK,
                                             carrier: carrier,
                                             trace_state_entry_key: "190@nr"
      assert_equal payload.to_s, trace_context_header_data.trace_state_payload.to_s
      assert_equal 'new=entry', trace_context_header_data.trace_state('new=entry')
    end

    def test_parse_tracestate_no_nr_entry
      carrier = make_inbound_carrier
      trace_context_header_data = TraceContext.parse format: NewRelic::FORMAT_NON_RACK,
                                             carrier: carrier,
                                             trace_state_entry_key: "190@nr"
      assert_nil trace_context_header_data.trace_state_payload
      assert_equal 'new=entry,other=asdf', trace_context_header_data.trace_state('new=entry')
    end

    def test_parse_tracestate_nr_entry_malformed
      carrier = make_inbound_carrier({'tracestate' => "190@nr=somethingincorrect"})
      trace_context_header_data = TraceContext.parse format: NewRelic::FORMAT_NON_RACK,
                                             carrier: carrier,
                                             trace_state_entry_key: "190@nr"

      refute trace_context_header_data.trace_state_payload, "no payload expected"
      assert_equal 'new=entry', trace_context_header_data.trace_state('new=entry')
      assert_metrics_recorded "Supportability/TraceContext/Parse/Exception"
      assert_metrics_recorded "Supportability/TraceContext/Parse/Exception"
    end

    def test_extract_trace_parent_nonzero_version
      carrier = make_inbound_carrier({
        NewRelic::TRACEPARENT_KEY => 'cc-12345678901234567890123456789012-1234567890123456-01'
      })
      trace_parent = TraceContext.send :extract_traceparent, NewRelic::FORMAT_NON_RACK, carrier
      assert TraceContext.send :trace_parent_valid?, trace_parent
      assert_equal 'cc', trace_parent['version']
      assert_equal '12345678901234567890123456789012', trace_parent['trace_id']
    end

    def test_extract_trace_parent_nonzero_version_with_trailing_fields
      carrier = make_inbound_carrier({
        NewRelic::TRACEPARENT_KEY => 'cc-12345678901234567890123456789012-1234567890123456-01-what-the-future-will-be-like'
      })
      trace_parent = TraceContext.send :extract_traceparent, NewRelic::FORMAT_NON_RACK, carrier
      assert TraceContext.send :trace_parent_valid?, trace_parent
      assert_equal 'cc', trace_parent['version']
      assert_equal '12345678901234567890123456789012', trace_parent['trace_id']
    end


    def test_extract_trace_parent_zero_version_with_trailing_fields
      carrier = make_inbound_carrier({
        NewRelic::TRACEPARENT_KEY => '00-12345678901234567890123456789012-1234567890123456-01-what-the-future-will-be-like'
      })
      trace_parent = TraceContext.send :extract_traceparent, NewRelic::FORMAT_NON_RACK, carrier
      refute TraceContext.send :trace_parent_valid?, trace_parent
    end

    def test_trace_parent_valid
      valid_trace_parent = {
        'version' => '00',
        'trace_id' => 'a8e67265afe2773a3c611b94306ee5c2',
        'parent_id' => 'fb1010463ea28a38',
        'trace_flags' => '01'
      }

      assert TraceContext.send :trace_parent_valid?, valid_trace_parent
    end

    def test_trace_parent_valid_invalid_trace_id
      invalid_trace_id = {
        'version' => '00',
        'trace_id' => '00000000000000000000000000000000',
        'parent_id' => 'fb1010463ea28a38',
        'trace_flags' => '01'
      }

      assert_false TraceContext.send :trace_parent_valid?, invalid_trace_id
    end

    def test_trace_parent_valid_invalid_parent_id
      invalid_trace_parent = {
        'version' => '00',
        'trace_id' => 'a8e67265afe2773a3c611b94306ee5c2',
        'parent_id' => '0000000000000000',
        'trace_flags' => '01'
      }

      assert_false TraceContext.send :trace_parent_valid?, invalid_trace_parent
    end

    def test_invalid_version
      invalid_trace_parent = {
        'version' => 'ff',
        'trace_id' => 'a8e67265afe2773a3c611b94306ee5c2',
        'parent_id' => 'fb1010463ea28a38',
        'trace_flags' => '01'
      }

      assert_false TraceContext.send :trace_parent_valid?, invalid_trace_parent
    end

    def test_trace_parent_valid_version_zero_with_extra_fields
      invalid_trace_parent = {
        'version' => '00',
        'trace_id' => 'a8e67265afe2773a3c611b94306ee5c2',
        'parent_id' => 'fb1010463ea28a38',
        'trace_flags' => '01',
        'undefined_fields' => '-these-are-some-extra-fields'
      }

      assert_false TraceContext.send :trace_parent_valid?, invalid_trace_parent
    end

    def test_trace_parent_valid_future_version_with_extra_fields
      invalid_trace_parent = {
        'version' => 'ff',
        'trace_id' => 'a8e67265afe2773a3c611b94306ee5c2',
        'parent_id' => 'fb1010463ea28a38',
        'trace_flags' => '01',
        'undefined_fields' => '-these-are-some-extra-fields'
      }

      assert_false TraceContext.send :trace_parent_valid?, invalid_trace_parent
    end

    def make_inbound_carrier options = {}
      {
        NewRelic::TRACEPARENT_KEY => '00-a8e67265afe2773a3c611b94306ee5c2-fb1010463ea28a38-01',
        NewRelic::TRACESTATE_KEY  => "other=asdf"
      }.update(options)
    end

    def make_payload
      in_transaction "test_txn" do |txn|
        return txn.distributed_tracer.create_trace_state_payload
      end
    end
  end
end
