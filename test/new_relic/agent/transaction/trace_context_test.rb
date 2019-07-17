# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path '../../../../test_helper', __FILE__

require 'new_relic/agent/trace_context'

module NewRelic
  module Agent
    class Transaction
      class TraceContextTest < Minitest::Test
        def setup
          nr_freeze_time

          @config = {
            :'trace_context.enabled' => true,
            :account_id => "190",
            :primary_application_id => "46954",
            :trusted_account_key => "999999",
            :disable_harvest_thread => true
          }

          NewRelic::Agent.config.add_config_for_testing(@config)
          uncache_trusted_account_key
        end

        def teardown
          NewRelic::Agent.config.remove_config(@config)
          NewRelic::Agent.config.reset_to_defaults
          NewRelic::Agent.drop_buffered_data
        end

        def test_insert_trace_context
          nr_freeze_time

          carrier = {}
          trace_state = nil
          trace_id = nil
          parent_id = nil

          in_transaction do |txn|
            txn.sampled = true
            txn.insert_trace_context carrier: carrier
            trace_state = txn.trace_state
            parent_id = txn.current_segment.guid
            trace_id = txn.trace_id
          end

          expected_trace_parent = "00-#{trace_id}-#{parent_id}-01"
          assert_equal expected_trace_parent, carrier['traceparent']

          assert_equal trace_state, carrier['tracestate']
        end

        def test_insert_trace_context_non_root
          parent_trace_context_data = nil
          trace_state = nil
          trace_id = nil

          in_transaction do |parent|
            parent.sampled = true
            payload = DistributedTracePayload.for_transaction parent
            parent_trace_context_data = make_trace_context_data trace_state_payload: payload
            trace_id = parent.trace_id
            trace_state = parent_trace_context_data.trace_state
          end

          carrier = {}
          child_trace_state_entry = nil
          parent_id = nil

          in_transaction do |child|
            child.accept_trace_context parent_trace_context_data
            child.insert_trace_context carrier: carrier
            child_trace_state_entry = DistributedTracePayload.for_transaction child
            parent_id = child.current_segment.guid
          end

          expected_trace_parent = "00-#{trace_id}-#{parent_id}-01"
          assert_equal expected_trace_parent, carrier['traceparent']

          # We expect trace state to now have our entry at the front
          trace_state_entry_key = NewRelic::Agent::TraceContext::AccountHelpers.trace_state_entry_key
          expected_trace_state = "#{trace_state_entry_key}=#{child_trace_state_entry.http_safe},#{trace_state}"
          assert_equal expected_trace_state, carrier['tracestate']
        end

        def test_insert_trace_context_only_other_vendors
          parent_trace_context_data = nil
          trace_state = nil
          trace_id = nil

          in_transaction do |parent|
            parent_trace_context_data = make_trace_context_data trace_state: ['other=asdf,other2=jkl;']
            trace_id = parent.trace_id
            trace_state = parent_trace_context_data.trace_state
          end

          carrier = {}
          child_trace_state_entry = nil
          parent_id = nil

          in_transaction do |child|
            child.accept_trace_context parent_trace_context_data
            child.insert_trace_context carrier: carrier
            child_trace_state_entry = DistributedTracePayload.for_transaction child
            parent_id = child.current_segment.guid
          end

          # We expect trace state to now have our entry at the front
          trace_state_entry_key = NewRelic::Agent::TraceContext::AccountHelpers.trace_state_entry_key
          expected_trace_state = "#{trace_state_entry_key}=#{child_trace_state_entry.http_safe},#{trace_state}"
          assert_equal expected_trace_state, carrier['tracestate']
        end

        def test_insert_trace_context_no_other_vendors
          parent_trace_context_data = nil
          trace_state = nil
          trace_id = nil

          in_transaction do |parent|
            parent.sampled = true
            payload = DistributedTracePayload.for_transaction parent
            parent_trace_context_data = make_trace_context_data trace_state_payload: payload, trace_state: []
            trace_id = parent.trace_id
            trace_state = parent_trace_context_data.trace_state
          end

          carrier = {}
          child_trace_state_entry = nil
          parent_id = nil

          in_transaction do |child|
            child.accept_trace_context parent_trace_context_data
            child.insert_trace_context carrier: carrier
            child_trace_state_entry = DistributedTracePayload.for_transaction child
            parent_id = child.current_segment.guid
          end

          expected_trace_parent = "00-#{trace_id}-#{parent_id}-01"
          assert_equal expected_trace_parent, carrier['traceparent']

          # We expect trace state to now have replaced our old entry with our new entry
          trace_state_entry_key = NewRelic::Agent::TraceContext::AccountHelpers.trace_state_entry_key
          expected_trace_state = "#{trace_state_entry_key}=#{child_trace_state_entry.http_safe}"
          assert_equal expected_trace_state, carrier['tracestate']

          # We expect the trace state not to be the same as the parent's trace state
          refute_match parent_trace_context_data.trace_state_payload.http_safe, carrier['tracestate']
        end

        def test_accept_trace_context_no_new_relic_parent
          trace_context_data = make_trace_context_data

          t = in_transaction do |txn|
            txn.accept_trace_context trace_context_data
          end

          assert_same trace_context_data, t.trace_context_data
          assert_nil t.parent_transaction_id
        end

        def test_accept_trace_state_actually_sets_transaction_attributes
          carrier = {}

          parent_txn = in_transaction 'parent' do |txn|
            txn.sampled = true
            txn.insert_trace_context carrier: carrier
          end

          trace_context_data = NewRelic::Agent::TraceContext.parse \
            carrier: carrier,
            trace_state_entry_key: NewRelic::Agent::TraceContext::AccountHelpers.trace_state_entry_key
          child_txn = in_transaction 'new' do |txn|
            txn.accept_trace_context trace_context_data
          end

          assert_equal parent_txn.guid, child_txn.parent_transaction_id
          assert_equal parent_txn.trace_id, child_txn.trace_id
          assert_equal parent_txn.sampled?, child_txn.sampled?
          assert_equal parent_txn.priority, child_txn.priority
        end

        def test_do_not_accept_trace_context_if_trace_context_disabled
          carrier = {}
          disabled_config = @config.merge({
            :'trace_context.enabled' => false
          })
          parent_txn = nil
          child_txn = nil

          with_config(disabled_config) do
            parent_txn = in_transaction 'parent' do |txn|
              txn.sampled = true
              txn.insert_trace_context carrier: carrier
            end

            trace_context_data = NewRelic::Agent::TraceContext.parse \
              carrier: carrier,
              trace_state_entry_key: "nr"


            child_txn = in_transaction 'child' do |txn|
              txn.accept_trace_context trace_context_data
            end
          end

          refute_equal parent_txn.guid, child_txn.parent_transaction_id
          assert_nil child_txn.parent_transaction_id
          refute_equal parent_txn.trace_id, child_txn.trace_id
        end

        def test_do_not_accept_trace_context_with_mismatching_account_ids
          carrier = {}
          account_one = @config.merge({
            trusted_account_key: '500'
          })
          account_two = @config.merge({
            account_id: '200',
            primary_application_id: '190011',
            trusted_account_key: '495590'
          })
          txn_one = nil
          txn_two = nil

          with_config(account_one) do
            txn_one = in_transaction 'parent' do |txn|
              txn.sampled = true
              txn.insert_trace_context carrier: carrier
            end
          end

          uncache_trusted_account_key

          with_config(account_two) do
            trace_context_data = NewRelic::Agent::TraceContext.parse \
              carrier: carrier,
              trace_state_entry_key: NewRelic::Agent::TraceContext::AccountHelpers.trace_state_entry_key
            txn_two = in_transaction 'child' do |txn|
              txn.accept_trace_context trace_context_data
            end
          end

          # Make sure the parent transaction did not affect the child transaction's attributes
          refute_equal txn_one.guid, txn_two.parent_transaction_id
          assert_nil txn_two.parent_transaction_id
          refute_equal txn_one.trace_id, txn_two.trace_id
          # Make sure the trace_state isn't affected either
          assert_nil txn_two.trace_context_data.instance_variable_get :@trace_state_payload
        end

        def test_accept_trace_context_mismatching_account_ids_matching_trust_key
          carrier = {}
          account_one = @config.merge({
            trusted_account_key: '500'
          })
          account_two = @config.merge({
            account_id: '200',
            primary_application_id: '190011',
            trusted_account_key: '500'
          })
          txn_one = nil
          txn_two = nil

          with_config(account_one) do
            txn_one = in_transaction 'parent' do |txn|
              txn.sampled = true
              txn.insert_trace_context carrier: carrier
            end
          end

          uncache_trusted_account_key

          with_config(account_two) do
            trace_context_data = NewRelic::Agent::TraceContext.parse \
              carrier: carrier,
              trace_state_entry_key: NewRelic::Agent::TraceContext::AccountHelpers.trace_state_entry_key
            txn_two = in_transaction 'child' do |txn|
              txn.accept_trace_context trace_context_data
            end
          end

          assert_equal txn_one.guid, txn_two.parent_transaction_id
          assert txn_two.parent_transaction_id
          assert_equal txn_one.trace_id, txn_two.trace_id
        end

        def test_do_not_accept_trace_context_if_trace_context_already_accepted
          in_transaction do |txn|
            trace_state_payload = txn.create_trace_state_payload
            trace_context_data = make_trace_context_data trace_state_payload: trace_state_payload

            assert txn.accept_trace_context(trace_context_data), "Expected first trace context to be accepted"
            refute txn.accept_trace_context(trace_context_data), "Expected second trace context not to be accepted"
          end
          assert_metrics_recorded "Supportability/TraceContext/AcceptPayload/Ignored/Multiple"
        end

        def test_do_not_accept_trace_context_if_txn_has_already_generated_trace_context
          carrier = {}

          in_transaction do |txn|
            txn.insert_trace_context carrier: carrier
            trace_context_data = make_trace_context_data

            refute txn.accept_trace_context trace_context_data
          end
          assert_metrics_recorded "Supportability/TraceContext/AcceptPayload/Ignored/CreateBeforeAccept"
        end

        def make_trace_context_data traceparent: "00-a8e67265afe2773a3c611b94306ee5c2-fb1010463ea28a38-01",
                                    trace_state_payload: nil,
                                    trace_state: ["other=asdf"]
            NewRelic::Agent::TraceContext::Data.new traceparent, trace_state_payload, trace_state
        end

        def uncache_trusted_account_key
          NewRelic::Agent::TraceContext::AccountHelpers.instance_variable_set :@trace_state_entry_key, nil
        end
      end
    end
  end
end
