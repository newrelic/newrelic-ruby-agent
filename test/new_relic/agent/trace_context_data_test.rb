# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path '../../../test_helper', __FILE__
require 'new_relic/agent/trace_context'
require 'new_relic/agent/distributed_trace_payload'

module NewRelic
  module Agent
    class TraceContext
      class TraceContextDataTest < Minitest::Test

        def test_tracestate_built_from_array
          other_entries = ['one', 'two']
          data = Data.new 'traceparent', 'tracestate_entry', other_entries

          assert_nil data.instance_variable_get :@trace_state
          refute_nil data.instance_variable_get :@other_trace_state_entries

          assert_equal 'new_entry,one,two', data.trace_state('new_entry')
          refute_nil data.instance_variable_get :@trace_state
          assert_nil data.instance_variable_get :@other_trace_state_entries
        end

        def test_trace_state_does_not_trim_unless_size_exceeds_512_bytes
          # Create a trace state array with 50 9 byte entries.  When joined
          # with a comma, this would be 499 bytes
          trace_state_array = (0...50).map { "#{random_text(2)}=#{random_text(6)}" }
          data = Data.new 'traceparent', 'payload', trace_state_array

          # setting the entry size to something <= 12 shouldn't trim the trace state
          new_entry = 'a' * 12
          trace_state = data.trace_state new_entry
          assert_equal 512, trace_state.length
        end

        def test_trace_state_trims_if_too_long
          # Create a trace state array with 50 9 byte entries.  When joined
          # with a comma, this would be 499 bytes
          trace_state_array = (0...50).map { "#{random_text(2)}=#{random_text(6)}" }
          data = Data.new 'traceparent', 'payload', trace_state_array

          # setting the entry size to something > 12 should result in a trimmed trace state
          new_entry = 'a' * 13
          trace_state = data.trace_state new_entry
          
          expected_size = 499 - 9 + 13
          assert_equal expected_size, trace_state.bytesize
        end

        LETTERS = ('a'..'z').to_a
        def random_text length
          letters = (0...length).map { LETTERS.sample }
          letters.join('')
        end
      end
    end
  end
end