# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      class SpanEventPrimitivePatchTest < Minitest::Test
        def test_for_segment_returns_three_element_array_when_no_links
          with_segment do |segment|
            event = SpanEventPrimitive.for_segment(segment)

            assert_equal 3, event.length
          end
        end

        def test_for_segment_returns_four_element_array_when_links_present
          link = stub_span_link('a' * 32, 'b' * 16)

          with_segment do |segment|
            segment.add_span_link(link)
            event = SpanEventPrimitive.for_segment(segment)

            assert_equal 4, event.length
            assert_kind_of Array, event[3]
          end
        end

        def test_for_span_links_returns_empty_when_no_links
          with_segment do |segment|
            result = SpanEventPrimitive.send(:for_span_links, segment)

            assert_empty result
          end
        end

        def test_for_span_links_returns_span_link_event_harvest
          hex_trace_id = 'abcd1234abcd1234abcd1234abcd1234'
          hex_span_id = '1234abcd1234abcd'
          link = stub_span_link(hex_trace_id, hex_span_id, {'user_attr' => 'value'})

          with_segment do |segment|
            segment.add_span_link(link)
            result = SpanEventPrimitive.send(:for_span_links, segment)

            assert_equal 1, result.length
            intrinsics, user_attrs, agent_attrs = result[0]

            assert_equal 'SpanLink', intrinsics['type']
            assert_equal segment.guid, intrinsics['id']
            assert_equal segment.transaction.trace_id, intrinsics['trace.id']
            assert_equal hex_span_id, intrinsics['linkedSpanId']
            assert_equal hex_trace_id, intrinsics['linkedTraceId']
            assert_kind_of Integer, intrinsics['timestamp']
            assert_equal 'value', user_attrs['user_attr']
            assert_empty(agent_attrs)
          end
        end

        def test_for_span_links_link_attributes_are_included_as_user_attributes
          link = stub_span_link('a' * 32, 'b' * 16, {'key1' => 'val1', 'key2' => 42})

          with_segment do |segment|
            segment.add_span_link(link)
            result = SpanEventPrimitive.send(:for_span_links, segment)
            _, user_attrs, _ = result[0]

            assert_equal 'val1', user_attrs['key1']
            assert_equal 42, user_attrs['key2']
          end
        end

        def test_for_segment_returns_three_element_array_when_no_span_events
          with_segment do |segment|
            event = SpanEventPrimitive.for_segment(segment)

            assert_equal 3, event.length
          end
        end

        def test_for_segment_returns_four_element_array_when_span_events_present
          with_segment do |segment|
            segment.add_span_event_event('my_event')
            event = SpanEventPrimitive.for_segment(segment)

            assert_equal 4, event.length
            assert_kind_of Array, event[3]
          end
        end

        def test_for_span_events_returns_empty_when_no_events
          with_segment do |segment|
            result = SpanEventPrimitive.send(:for_span_events, segment)

            assert_empty result
          end
        end

        def test_for_span_events_returns_correct_intrinsics
          t = Time.now

          with_segment do |segment|
            segment.add_span_event_event('TestEvent', attributes: {'attr_key' => 'attr_val'}, timestamp: t)
            result = SpanEventPrimitive.send(:for_span_events, segment)

            assert_equal 1, result.length
            intrinsics, user_attrs, agent_attrs = result[0]

            assert_equal 'SpanEvent', intrinsics['type']
            assert_equal segment.guid, intrinsics['span.id']
            assert_equal segment.transaction.trace_id, intrinsics['trace.id']
            assert_equal 'TestEvent', intrinsics['name']
            assert_kind_of Integer, intrinsics['timestamp']
            assert_equal Integer(t.to_f * 1000.0), intrinsics['timestamp']
            assert_empty agent_attrs
          end
        end

        def test_for_span_events_places_event_attributes_as_user_attributes
          with_segment do |segment|
            segment.add_span_event_event('AttrEvent', attributes: {'key1' => 'val1', 'key2' => 42})
            result = SpanEventPrimitive.send(:for_span_events, segment)
            _, user_attrs, _ = result[0]

            assert_equal 'val1', user_attrs['key1']
            assert_equal 42, user_attrs['key2']
          end
        end

        def test_for_span_events_empty_user_attributes_when_none_provided
          with_segment do |segment|
            segment.add_span_event_event('NoAttrEvent')
            result = SpanEventPrimitive.send(:for_span_events, segment)
            _, user_attrs, _ = result[0]

            assert_empty(user_attrs)
          end
        end

        def test_sanitize_event_attributes_returns_empty_when_custom_attributes_disabled
          with_config(:'custom_attributes.enabled' => false) do
            with_segment do |segment|
              result = SpanEventPrimitive.send(:sanitize_event_attributes, {'key' => 'value'})

              assert_empty result
            end
          end
        end

        def test_sanitize_event_attributes_expands_array_values_to_indexed_keys
          with_segment do |segment|
            result = SpanEventPrimitive.send(:sanitize_event_attributes, {'arr' => [1, 2, 3]})

            assert_equal 1, result['arr.0']
            assert_equal 2, result['arr.1']
            assert_equal 3, result['arr.2']
          end
        end

        def test_sanitize_event_attributes_coerces_unsupported_scalar_types_to_string
          with_segment do |segment|
            result = SpanEventPrimitive.send(:sanitize_event_attributes, {'ratio' => Rational(1, 2)})

            assert_equal '#<Rational>', result['ratio']
          end
        end

        def test_sanitize_event_attributes_drops_non_finite_float_values
          with_segment do |segment|
            result = SpanEventPrimitive.send(:sanitize_event_attributes, {
              'infinity' => Float::INFINITY,
              'nan' => Float::NAN,
              'valid' => 42
            })

            refute result.key?('infinity')
            refute result.key?('nan')
            assert result.key?('valid')
          end
        end

        def test_sanitize_event_attributes_truncates_long_string_values
          with_segment do |segment|
            result = SpanEventPrimitive.send(:sanitize_event_attributes, {'key' => 'x' * 300})

            assert result['key'].bytesize <= NewRelic::Agent::Attributes::VALUE_LIMIT
          end
        end

        def test_sanitize_event_attributes_drops_long_keys_with_warning
          with_segment do |segment|
            long_key = 'k' * 300

            NewRelic::Agent.logger.expects(:warn).once
            result = SpanEventPrimitive.send(:sanitize_event_attributes, {long_key => 'value'})

            refute result.key?(long_key)
          end
        end

        def test_sanitize_event_attributes_caps_count_at_limit_with_warning
          with_segment do |segment|
            attrs = (NewRelic::Agent::Attributes::COUNT_LIMIT + 1).times.each_with_object({}) { |i, h| h["key_#{i}"] = i }

            NewRelic::Agent.logger.expects(:warn).once
            result = SpanEventPrimitive.send(:sanitize_event_attributes, attrs)

            assert_equal NewRelic::Agent::Attributes::COUNT_LIMIT, result.size
          end
        end

        def test_sanitize_event_attributes_respects_attribute_filter_exclusions
          with_config(:'attributes.exclude' => ['secret_key']) do
            with_segment do |segment|
              result = SpanEventPrimitive.send(:sanitize_event_attributes, {
                'secret_key' => 'secret',
                'safe_key' => 'safe'
              })

              refute result.key?('secret_key')
              assert_equal 'safe', result['safe_key']
            end
          end
        end

        def test_span_events_combined_with_span_links_in_same_index_3_array
          link = stub_span_link('a' * 32, 'b' * 16)

          with_segment do |segment|
            segment.add_span_link(link)
            segment.add_span_event_event('CombinedEvent')
            event = SpanEventPrimitive.for_segment(segment)

            assert_equal 4, event.length
            extras = event[3]
            types = extras.map { |e| e[0]['type'] }

            assert_includes types, 'SpanLink'
            assert_includes types, 'SpanEvent'
          end
        end

        private

        def stub_span_link(hex_trace_id, hex_span_id, attributes = {})
          ctx = Struct.new(:hex_trace_id, :hex_span_id).new(hex_trace_id, hex_span_id)
          Struct.new(:span_context, :attributes).new(ctx, attributes)
        end
      end
    end
  end
end
