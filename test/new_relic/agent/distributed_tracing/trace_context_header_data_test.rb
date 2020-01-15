# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path '../../../../test_helper', __FILE__

module NewRelic
  module Agent
    module DistributedTracing
      class TraceContext
        class TraceContextHeaderDataTest < Minitest::Test

          def test_tracestate_built_from_array
            other_entries = ['one', 'two']
            header_data = HeaderData.new 'traceparent', 'tracestate_entry', other_entries, 0, ''

            assert_nil header_data.instance_variable_get :@trace_state
            refute_nil header_data.instance_variable_get :@trace_state_entries

            assert_equal 'new_entry,one,two', header_data.trace_state('new_entry')
            refute_nil header_data.instance_variable_get :@trace_state
            assert_nil header_data.instance_variable_get :@trace_state_entries
          end

          def test_trace_state_does_not_trim_unless_size_exceeds_512_bytes
            # Create a trace state array with 50 9 byte entries.  When joined
            # with a comma, this would be 499 bytes
            trace_state_array = (0...50).map { "#{random_text(2)}=#{random_text(6)}" }
            header_data = HeaderData.new 'traceparent', 'payload', trace_state_array, 499, ''

            # setting the entry size to something <= 12 shouldn't trim the trace state
            new_entry = 'a' * 12
            trace_state = header_data.trace_state new_entry
            assert_equal 512, trace_state.length
          end

          def test_trace_state_trims_if_too_long
            # Create a trace state array with 50 9 byte entries.  When joined
            # with a comma, this would be 499 bytes
            trace_state_array = (0...50).map { "#{random_text(2)}=#{random_text(6)}" }
            header_data = HeaderData.new 'traceparent', 'payload', trace_state_array, 499, ''

            # setting the entry size to something > 12 should result in a trimmed trace state
            new_entry = 'a' * 13
            trace_state = header_data.trace_state new_entry

            expected_size = 499 - 9 + 13
            assert_equal expected_size, trace_state.bytesize
          end

          def test_trace_state_trims_large_entries_if_total_size_is_greater_than_512_bytes
            trace_state_array = [
              "#{random_text(2)}=#{random_text(130)}", # 133 bytes
            ]
            # also add 500 more bytes
            trace_state_array += (0...50).map { "#{random_text(2)}=#{random_text(6)}" }
            header_data = HeaderData.new 'traceparent', 'payload', trace_state_array, 550, ''

            trace_state = header_data.trace_state 'new=entry'
            # if the big 133 byte entry gets dropped, the joined trace state
            # will be 50 nine byte entries plus 49 commas plus the new entry,
            # which is 9 more bytes, plus one more comma, so 50*9 + 49 + 9 + 1
            expected_size = (50 * 9) + 49 + 9 + 1
            assert_equal expected_size, trace_state.bytesize
          end

          def test_trace_state_doesnt_trim_large_entries_if_total_size_is_less_than_512_bytes
            trace_state_array = [
              'one=value',
              "#{random_text(2)}=#{random_text(130)}", # 133 bytes
              'two=value'
            ]
            header_data = HeaderData.new 'traceparent', 'payload', trace_state_array, 155, ''

            trace_state = header_data.trace_state 'new=entry'
            expected_trace_state = "new=entry,#{trace_state_array.join(',')}"
            assert_equal expected_trace_state, trace_state
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
end