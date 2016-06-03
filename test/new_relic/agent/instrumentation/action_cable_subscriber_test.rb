# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

if defined?(::Rails) && ::Rails::VERSION::MAJOR.to_i >= 5

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/instrumentation/action_cable_subscriber'


module NewRelic
  module Agent
    module Instrumentation
      class ActionCableSubscriberTest < Minitest::Test

        def setup
          freeze_time
          @subscriber = ActionCableSubscriber.new

          NewRelic::Agent.drop_buffered_data
          @stats_engine = NewRelic::Agent.instance.stats_engine
          @stats_engine.clear_stats
          NewRelic::Agent.manual_start
          NewRelic::Agent::TransactionState.tl_clear_for_testing
        end

        def teardown
          NewRelic::Agent.shutdown
          @stats_engine.clear_stats
        end

        def test_creates_web_transaction
          @subscriber.start('perform_action.action_cable', :id, payload_for_perform_action)
          assert NewRelic::Agent::TransactionState.tl_get.in_web_transaction?
          advance_time(1.0)
          @subscriber.finish('perform_action.action_cable', :id, payload_for_perform_action)

          assert_equal('Controller/ActionCable/TestChannel/test_action',
                       NewRelic::Agent.instance.transaction_sampler.last_sample.transaction_name)
          assert_equal('Controller/ActionCable/TestChannel/test_action',
                       NewRelic::Agent.instance.transaction_sampler.last_sample.root_node.called_nodes[0].metric_name)
        end

        def test_records_apdex_metrics
          @subscriber.start('perform_action.action_cable', :id, payload_for_perform_action)
          advance_time(1.5)
          @subscriber.finish('perform_action.action_cable', :id, payload_for_perform_action)

          expected_values = { :apdex_f => 0, :apdex_t => 1, :apdex_s => 0 }
          assert_metrics_recorded(
            'Apdex/ActionCable/TestChannel/test_action' => expected_values,
            'Apdex' => expected_values
          )
        end

        def test_sets_default_transaction_name_on_start
          @subscriber.start('perform_action.action_cable', :id, payload_for_perform_action)
          assert_equal 'Controller/ActionCable/TestChannel/test_action', NewRelic::Agent::Transaction.tl_current.best_name
        ensure
          @subscriber.finish('perform_action.action_cable', :id, payload_for_perform_action)
        end

        def test_sets_default_transaction_keeps_name_through_stop
          @subscriber.start('perform_action.action_cable', :id, payload_for_perform_action)
          txn = NewRelic::Agent::Transaction.tl_current
          @subscriber.finish('perform_action.action_cable', :id, payload_for_perform_action)
          assert_equal 'Controller/ActionCable/TestChannel/test_action', txn.best_name
        end

        def test_sets_transaction_name
          @subscriber.start('perform_action.action_cable', :id, payload_for_perform_action)
          NewRelic::Agent.set_transaction_name('something/else')
          assert_equal 'Controller/ActionCable/something/else', NewRelic::Agent::Transaction.tl_current.best_name
        ensure
          @subscriber.finish('perform_action.action_cable', :id, payload_for_perform_action)
        end

        def test_sets_transaction_name_holds_through_stop
          @subscriber.start('perform_action.action_cable', :id, payload_for_perform_action)
          txn = NewRelic::Agent::Transaction.tl_current
          NewRelic::Agent.set_transaction_name('something/else')
          @subscriber.finish('perform_action.action_cable', :id, payload_for_perform_action)
          assert_equal 'Controller/ActionCable/something/else', txn.best_name
        end

        def test_creates_tt_node_for_transmit
          @subscriber.start('perform_action.action_cable', :id, payload_for_perform_action)
          assert NewRelic::Agent::TransactionState.tl_get.in_web_transaction?
          @subscriber.start('transmit.action_cable', :id, payload_for_transmit)
          advance_time(1.0)
          @subscriber.finish('transmit.action_cable', :id, payload_for_transmit)
          @subscriber.finish('perform_action.action_cable', :id, payload_for_perform_action)

          sample = NewRelic::Agent.instance.transaction_sampler.last_sample

          assert_equal('Controller/ActionCable/TestChannel/test_action', sample.transaction_name)
          metric_name = 'Ruby/ActionCable/TestChannel/transmit'
          refute_nil(find_node_with_name(sample, metric_name), "Expected trace to have node with name: #{metric_name}")
        end

        def test_records_unscoped_metrics_but_does_not_create_trace_for_transmit_outside_of_active_txn
          @subscriber.start('transmit.action_cable', :id, payload_for_transmit)
          advance_time(1.0)
          @subscriber.finish('transmit.action_cable', :id, payload_for_transmit)

          sample = NewRelic::Agent.instance.transaction_sampler.last_sample

          assert_nil sample, "Did not expect a transaction to be created for transmit"
          assert_metrics_recorded ['Ruby/ActionCable/TestChannel/transmit']
        end

        def payload_for_perform_action action = 'test_action'
          {:channel_class => "TestChannel", :action => action.to_sym, :data => {"action"=>"#{action}"}}
        end

        def payload_for_transmit data = {}, via = nil
          {:channel_class => "TestChannel", :data => data, :via => via}
        end
      end
    end
  end
end

end
