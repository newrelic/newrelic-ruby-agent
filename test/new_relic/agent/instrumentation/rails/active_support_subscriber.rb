# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../../test_helper'

module NewRelic
  module Agent
    module Instrumentation
      class ActiveSupportSubscriberTest < Minitest::Test
        DEFAULT_STORE = 'MemCacheStore'
        METRIC_PREFIX = 'Ruby/ActiveSupport/'
        DEFAULT_PARAMS = {key: fake_guid(32), store: DEFAULT_STORE}
        DEFAULT_EVENT = 'cache_read.active_support'

        def setup
          nr_freeze_process_time
          @subscriber = ActiveSupportSubscriber.new
          @id = fake_guid(32)

          NewRelic::Agent.drop_buffered_data
        end

        def teardown
          NewRelic::Agent.drop_buffered_data
        end

        def test_start_when_not_traced
          @subscriber.state.stub :is_execution_traced?, false do
            in_transaction do |txn|
              @subscriber.start(DEFAULT_EVENT, @id, {})

              assert_empty txn.segments
            end
          end
        end

        def test_finish_when_not_traced
          @subscriber.state.stub :is_execution_traced?, false do
            in_transaction do |txn|
              @subscriber.finish(DEFAULT_EVENT, @id, {})

              assert_empty txn.segments
            end
          end
        end

        def test_metrics_recorded_for_known_methods
          method_name_mapping = {
            'cache_read.active_support' => 'read'.freeze,
            'cache_generate.active_support' => 'generate'.freeze,
            'cache_fetch_hit.active_support' => 'fetch_hit'.freeze,
            'cache_write.active_support' => 'write'.freeze,
            'cache_delete.active_support' => 'delete'.freeze,
            'cache_exist?.active_support' => 'exist?'.freeze
          }

          in_transaction('test') do
            method_name_mapping.keys.each do |event_name|
              generate_event(event_name)
            end
          end

          method_name_mapping.values.each do |method_name|
            assert_metrics_recorded "#{METRIC_PREFIX}#{DEFAULT_STORE}/#{method_name}"
          end
        end

        def test_metric_recorded_for_new_event_names
          in_transaction('test') do
            generate_event('cache_new_method.active_support')
          end

          assert_metrics_recorded "#{METRIC_PREFIX}#{DEFAULT_STORE}/new_method"
        end

        def test_failsafe_if_event_does_not_match_expected_pattern
          in_transaction('test') do
            generate_event('charcuterie_build_a_board_workshop')
          end

          assert_metrics_recorded "#{METRIC_PREFIX}#{DEFAULT_STORE}/Unknown"
        end

        def test_key_recorded_as_attribute_on_traces
          key = 'blades'
          txn = in_transaction('test') do
            generate_event('cache_read.active_support', key: key, hit: false)
          end

          trace = last_transaction_trace
          tt_node = find_node_with_name(trace, "#{METRIC_PREFIX}#{DEFAULT_STORE}/read")

          assert_equal key, tt_node.params[:key]
        end

        def test_hit_recorded_as_attribute_on_traces
          txn = in_transaction('test') do
            generate_event('cache_read.active_support', DEFAULT_PARAMS.merge(hit: false))
          end

          trace = last_transaction_trace
          tt_node = find_node_with_name(trace, "#{METRIC_PREFIX}#{DEFAULT_STORE}/read")

          assert tt_node.params.key?(:hit)
          refute tt_node.params[:hit]
        end

        def test_super_operation_recorded_as_attribute_on_traces
          txn = in_transaction('test') do
            generate_event('cache_read.active_support', DEFAULT_PARAMS.merge(super_operation: nil))
          end

          trace = last_transaction_trace
          tt_node = find_node_with_name(trace, "#{METRIC_PREFIX}#{DEFAULT_STORE}/read")

          assert tt_node.params.key?(:super_operation)
          refute tt_node.params[:super_operation]
        end

        def test_segment_created
          in_transaction('test') do
            txn = NewRelic::Agent::Tracer.current_transaction

            assert_equal 1, txn.segments.size

            generate_event('cache_write.active_support', key: 'blade')

            assert_equal 2, txn.segments.size
            assert_equal "#{METRIC_PREFIX}#{DEFAULT_STORE}/write", txn.segments.last.name
            assert_predicate txn.segments.last, :finished?, "Segment #{txn.segments.last.name} was never finished.  "
          end
        end

        def test_records_span_level_error
          exception_class = StandardError
          exception_msg = 'Natural 1'
          exception = exception_class.new(msg = exception_msg)
          # :exception_object was added in Rails 5 and above
          params = {:exception_object => exception, :exception => [exception_class.name, exception_msg]}

          txn = nil

          in_transaction do |test_txn|
            txn = test_txn
            generate_event('cache_fetch_hit.active_support', params)
          end

          assert_segment_noticed_error txn, /fetch/i, exception_class.name, /Natural 1/i
        end

        def test_pop_segment_returns_false
          @subscriber.stub :pop_segment, nil do
            txn = in_transaction do |txn|
              @subscriber.finish(DEFAULT_EVENT, @id, {})
            end

            assert txn.segments.none? { |s| s.name.include?('ActiveSupport') }
          end
        end

        def test_an_actual_active_storage_cache_write
          unless defined?(ActiveSupport::VERSION::MAJOR) && ActiveSupport::VERSION::MAJOR >= 5
            skip 'Test restricted to Active Support v5+'
          end

          in_transaction do |txn|
            store = ActiveSupport::Cache::MemoryStore
            key = 'city'
            store.new.write(key, 'Walla Walla')
            segment = txn.segments.last

            assert_equal 2, txn.segments.size

            # the :store key is only in the payload for Rails 6.1+
            rails61 = Gem::Version.new(ActiveSupport::VERSION::STRING) >= Gem::Version.new('6.1.0')
            segment_name = if rails61
              "Ruby/ActiveSupport/#{store}/write"
            else
              'Ruby/ActiveSupport/write'
            end

            assert_equal segment_name, segment.name
            assert_equal key, segment.params[:key]
            assert_equal store.to_s, segment.params[:store] if rails61
          end
        end

        private

        def generate_event(event_name, attributes = {})
          payload = DEFAULT_PARAMS.merge(attributes)
          @subscriber.start(event_name, @id, payload)
          yield if block_given?
          @subscriber.finish(event_name, @id, payload)
        end
      end
    end
  end
end
