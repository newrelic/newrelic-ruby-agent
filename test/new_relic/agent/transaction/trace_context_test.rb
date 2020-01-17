# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path '../../../../test_helper', __FILE__

module NewRelic
  module Agent
    class Transaction
      class TraceContextTest < Minitest::Test
        def setup
          nr_freeze_time

          @config = {
            :'distributed_tracing.enabled' => true,
            :'distributed_tracing.format' => 'w3c',
            :'span_events.enabled' => true,
            :account_id => "190",
            :primary_application_id => "46954",
            :trusted_account_key => "999999",
            :disable_harvest_thread => true,
          }
          NewRelic::Agent.agent.stubs(:connected?).returns(true)
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
          inserted = false

          txn = in_transaction do |t|
            t.sampled = true
            inserted = t.distributed_tracer.insert_trace_context carrier: carrier
            trace_state = t.distributed_tracer.create_trace_state
            parent_id = t.current_segment.guid
            trace_id = t.trace_id
          end

          assert inserted
          assert txn.distributed_tracer.trace_context_inserted?

          expected_trace_parent = "00-#{trace_id}-#{parent_id}-01"
          assert_equal expected_trace_parent, carrier['traceparent']

          assert_equal trace_state, carrier['tracestate']

          assert_metrics_recorded "Supportability/TraceContext/Create/Success"
        end

        def test_insert_trace_context_non_root
          parent_trace_context_header_data = nil
          other_trace_state = nil
          trace_id = nil

          in_transaction do |parent|
            parent.sampled = true
            payload = parent.distributed_tracer.create_trace_state_payload
            trace_parent = make_trace_parent({'trace_id' => parent.trace_id, 'parent_id' => parent.guid})
            parent_trace_context_header_data = make_trace_context_header_data \
              trace_parent: trace_parent,
              trace_state_payload: payload
            trace_id = parent.trace_id
            other_trace_state = parent_trace_context_header_data.instance_variable_get :@trace_state_entries
          end

          carrier = {}
          child_trace_state_payload = nil
          parent_id = nil

          in_transaction do |child|
            child.distributed_tracer.accept_trace_context parent_trace_context_header_data
            child.distributed_tracer.insert_trace_context carrier: carrier
            child_trace_state_payload = child.distributed_tracer.create_trace_state_payload
            parent_id = child.current_segment.guid
          end

          expected_trace_parent = "00-#{trace_id}-#{parent_id}-01"
          assert_equal expected_trace_parent, carrier['traceparent']

          # We expect trace state to now have our entry at the front
          trace_state_entry_key = NewRelic::Agent::DistributedTracing::TraceContext::AccountHelpers.trace_state_entry_key
          expected_trace_state = "#{trace_state_entry_key}=#{child_trace_state_payload.to_s},#{other_trace_state.join('.')}"
          assert_equal expected_trace_state, carrier['tracestate']
        end

        def test_insert_trace_context_only_other_vendors
          parent_trace_context_header_data = nil
          other_trace_state = nil

          in_transaction do |parent|
            parent.sampled = true
            parent_trace_context_header_data = make_trace_context_header_data trace_state: ['other=asdf,other2=jkl;']
            other_trace_state = parent_trace_context_header_data.instance_variable_get :@trace_state_entries
          end

          carrier = {}
          child_trace_state_payload = nil

          in_transaction do |child|
            child.sampled = true
            child.distributed_tracer.accept_trace_context parent_trace_context_header_data
            child.distributed_tracer.insert_trace_context carrier: carrier
            child_trace_state_payload = child.distributed_tracer.create_trace_state_payload
          end

          # We expect trace state to now have our entry at the front
          trace_state_entry_key = NewRelic::Agent::DistributedTracing::TraceContext::AccountHelpers.trace_state_entry_key
          expected_trace_state = "#{trace_state_entry_key}=#{child_trace_state_payload},#{other_trace_state.join(',')}"
          assert_equal expected_trace_state, carrier['tracestate']
        end

        def test_insert_trace_context_no_other_vendors
          parent_trace_context_header_data = nil

          in_transaction do |parent|
            parent.sampled = true
            payload = parent.distributed_tracer.create_trace_state_payload
            trace_parent = make_trace_parent({'trace_id' => parent.trace_id, 'parent_id' => parent.guid})
            parent_trace_context_header_data = make_trace_context_header_data \
              trace_parent: trace_parent,
              trace_state_payload: payload,
              trace_state: []
          end

          carrier = {}
          child_trace_state_payload = nil
          parent_id = nil

          in_transaction do |child|
            child.distributed_tracer.accept_trace_context parent_trace_context_header_data
            child.distributed_tracer.insert_trace_context carrier: carrier
            child_trace_state_payload = child.distributed_tracer.create_trace_state_payload
            parent_id = child.current_segment.guid
          end

          expected_trace_parent = "00-#{parent_trace_context_header_data.trace_id}-#{parent_id}-01"
          assert_equal expected_trace_parent, carrier['traceparent']

          # We expect trace state to now have replaced our old entry with our new entry
          trace_state_entry_key = NewRelic::Agent::DistributedTracing::TraceContext::AccountHelpers.trace_state_entry_key
          expected_trace_state = "#{trace_state_entry_key}=#{child_trace_state_payload}"
          assert_equal expected_trace_state, carrier['tracestate']

          # We expect the trace state not to be the same as the parent's trace state
          refute_match parent_trace_context_header_data.trace_state_payload.to_s, carrier['tracestate']
        end

        def test_accept_trace_context_no_new_relic_parent
          trace_context_header_data = make_trace_context_header_data

          t = in_transaction do |txn|
            txn.distributed_tracer.accept_trace_context trace_context_header_data
          end

          assert_same trace_context_header_data, t.distributed_tracer.trace_context_header_data
          assert_nil t.parent_transaction_id
        end

        def test_accept_trace_state_actually_sets_transaction_attributes
          carrier = {}

          parent_txn = in_transaction 'parent' do |txn|
            txn.sampled = true
            txn.distributed_tracer.insert_trace_context carrier: carrier
          end

          trace_context_header_data = NewRelic::Agent::DistributedTracing::TraceContext.parse \
            carrier: carrier,
            trace_state_entry_key: NewRelic::Agent::DistributedTracing::TraceContext::AccountHelpers.trace_state_entry_key
          child_txn = in_transaction 'new' do |txn|
            txn.distributed_tracer.accept_trace_context trace_context_header_data
          end

          assert_equal parent_txn.guid, child_txn.parent_transaction_id
          assert_equal parent_txn.trace_id, child_txn.trace_id
          assert_equal parent_txn.sampled?, child_txn.sampled?
          assert_equal parent_txn.priority, child_txn.priority
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
              txn.distributed_tracer.insert_trace_context carrier: carrier
            end
          end

          uncache_trusted_account_key

          with_config(account_two) do
            trace_context_header_data = NewRelic::Agent::DistributedTracing::TraceContext.parse \
              carrier: carrier,
              trace_state_entry_key: NewRelic::Agent::DistributedTracing::TraceContext::AccountHelpers.trace_state_entry_key
            txn_two = in_transaction 'child' do |txn|
              txn.distributed_tracer.accept_trace_context trace_context_header_data
            end
          end

          # even though the two accounts are unrelated, they are still part of
          # the same trace
          assert_equal txn_one.trace_id, txn_two.trace_id

          # Make sure the parent transaction did not affect the child transaction's attributes
          refute_equal txn_one.guid, txn_two.parent_transaction_id
          assert_nil txn_two.parent_transaction_id
          # Make sure the trace_state isn't affected either
          assert_nil txn_two.distributed_tracer.trace_context_header_data.trace_state_payload
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
              txn.distributed_tracer.insert_trace_context carrier: carrier
            end
          end

          uncache_trusted_account_key

          with_config(account_two) do
            trace_context_header_data = NewRelic::Agent::DistributedTracing::TraceContext.parse \
              carrier: carrier,
              trace_state_entry_key: NewRelic::Agent::DistributedTracing::TraceContext::AccountHelpers.trace_state_entry_key
            txn_two = in_transaction 'child' do |txn|
              txn.distributed_tracer.accept_trace_context trace_context_header_data
            end
          end

          assert_equal txn_one.guid, txn_two.parent_transaction_id
          assert txn_two.parent_transaction_id
          assert_equal txn_one.trace_id, txn_two.trace_id
        end

        def test_do_not_accept_trace_context_if_trace_context_already_accepted
          in_transaction do |txn|
            txn.sampled = true
            trace_state_payload = txn.distributed_tracer.create_trace_state_payload
            trace_context_header_data = make_trace_context_header_data trace_state_payload: trace_state_payload

            assert txn.distributed_tracer.accept_trace_context(trace_context_header_data), "Expected first trace context to be accepted"
            refute txn.distributed_tracer.accept_trace_context(trace_context_header_data), "Expected second trace context not to be accepted"
          end
          assert_metrics_recorded "Supportability/TraceContext/Accept/Ignored/Multiple"
        end

        def test_records_a_no_nr_entry_trace_state_metric
          parent_trace_context_header_data = nil

          in_transaction do |parent|
            parent.sampled = true
            parent_trace_context_header_data = make_trace_context_header_data trace_state: ['other=asdf,other2=jkl;']
          end

          carrier = {}

          in_transaction do |child|
            child.sampled = true
            child.distributed_tracer.accept_trace_context parent_trace_context_header_data
            child.distributed_tracer.insert_trace_context carrier: carrier
          end

          assert_metrics_recorded "Supportability/TraceContext/TraceState/NoNrEntry"
        end

        def test_records_an_invalid_trace_state_metric
          in_transaction do |txn|
            txn.sampled = true
            trace_state_payload = txn.distributed_tracer.create_trace_state_payload
            trace_context_header_data = make_trace_context_header_data trace_state_payload: trace_state_payload
            trace_state_payload.stubs(:valid?).returns(false)
            refute txn.distributed_tracer.accept_trace_context(trace_context_header_data), "Expected trace context to be rejected"
          end

          assert_metrics_recorded "Supportability/TraceContext/TraceState/InvalidPayload"
        end

        def test_do_not_accept_trace_context_if_txn_has_already_generated_trace_context
          carrier = {}

          in_transaction do |txn|
            txn.sampled = true
            txn.distributed_tracer.insert_trace_context carrier: carrier
            trace_context_header_data = make_trace_context_header_data

            refute txn.distributed_tracer.accept_trace_context trace_context_header_data
          end
          assert_metrics_recorded "Supportability/TraceContext/Accept/Ignored/CreateBeforeAccept"
        end

        def test_creates_trace_context_payload
          nr_freeze_time

          payload = nil
          parent_id = nil
          now_ms = (Time.now.to_f * 1000).round

          txn = in_transaction do |t|
            t.sampled = true
            payload = t.distributed_tracer.create_trace_state_payload
            parent_id = t.current_segment.guid
          end

          assert_equal '190', payload.parent_account_id
          assert_equal '46954', payload.parent_app_id
          assert_equal parent_id, payload.id
          assert_equal txn.guid, payload.transaction_id
          assert_equal txn.sampled?, payload.sampled
          assert_equal txn.priority, payload.priority
          assert_equal now_ms, payload.timestamp
        end

        def test_accept_trace_context_payload_from_browser
          # Browser payloads don't contain a transaction id, sampled flag, or priority
          # The transaction that receives one should come up with its own
          carrier = {
            'traceparent' => '00-a8e67265afe2773a3c611b94306ee5c2-0996096a36a1cd29-01',
            'tracestate' => '190@nr=0-1-212311-51424-0996096a36a1cd29----1482959525577'
          }

          trace_context_header_data = NewRelic::Agent::DistributedTracing::TraceContext.parse \
            carrier: carrier,
            trace_state_entry_key: '190@nr'

          txn = in_transaction do |t|
            t.distributed_tracer.accept_trace_context trace_context_header_data
          end

          assert_equal 'a8e67265afe2773a3c611b94306ee5c2', txn.trace_id
          refute_nil txn.distributed_tracer.trace_context_header_data
          assert_nil txn.parent_transaction_id
          refute_nil txn.guid
          refute_nil txn.sampled?
          refute_nil txn.priority
        end

        def make_trace_parent options
          {
            'version' => '00',
            'trace_id' => '',
            'parent_id' => '',
            'sampled' => '01'
          }.update options
        end

        def make_trace_context_header_data trace_parent: "00-a8e67265afe2773a3c611b94306ee5c2-fb1010463ea28a38-01",
                                    trace_state_payload: nil,
                                    trace_state: ["other=asdf"],
                                    trace_state_vendors: ''
            NewRelic::Agent::DistributedTracing::TraceContext::HeaderData.new trace_parent, trace_state_payload, trace_state, 10, trace_state_vendors
        end

        def uncache_trusted_account_key
          NewRelic::Agent::DistributedTracing::TraceContext::AccountHelpers.instance_variable_set :@trace_state_entry_key, nil
        end
      end
    end
  end
end
