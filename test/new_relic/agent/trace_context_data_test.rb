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

          assert_nil data.instance_variable_get :@tracestate
          refute_nil data.instance_variable_get :@other_trace_state_entries

          assert_equal 'one,two', data.tracestate
          refute_nil data.instance_variable_get :@tracestate
          assert_nil data.instance_variable_get :@other_trace_state_entries
        end


        def test_tracestate_trims_if_too_log
          # Create a trace state array with 50 9 byte entries.  When joined
          # with a comma, this would be 499 bytes
          tracestate_array = (0...50).map { "#{random_text(2)}=#{random_text(6)}" }
          data = Data.new 'traceparent', 'payload', tracestate_array

          # setting the entry size to something <= 12 shouldn't change the length
          # of the array
          (0..12).each do |size|
            data.set_entry_size size
            resulting_array = data.instance_variable_get :@other_trace_state_entries
            assert_equal 50, resulting_array.length, "Setting entry size to #{size} should not trim a 499 byte array"
          end

          # setting the entry size to something larger that 12 should trim the array
          data.set_entry_size 13
          resulting_array = data.instance_variable_get :@other_trace_state_entries
          assert_equal 49, resulting_array.length, "Setting entry size to 13 should not trim a 499 byte array"
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