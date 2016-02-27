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
          @subscriber.start('perform_action.action_cable', :id, payload)
          assert NewRelic::Agent::TransactionState.tl_get.in_web_transaction?
          advance_time(1.0)
          @subscriber.finish('perform_action.action_cable', :id, payload)

          assert_equal('Controller/ActionCable/TestChannel/test_action',
                       NewRelic::Agent.instance.transaction_sampler.last_sample.transaction_name)
          assert_equal('Controller/ActionCable/TestChannel/test_action',
                       NewRelic::Agent.instance.transaction_sampler.last_sample.root_node.called_nodes[0].metric_name)
        end

        def test_records_apdex_metrics
          @subscriber.start('perform_action.action_cable', :id, payload)
          advance_time(1.5)
          @subscriber.finish('perform_action.action_cable', :id, payload)

          expected_values = { :apdex_f => 0, :apdex_t => 1, :apdex_s => 0 }
          assert_metrics_recorded(
            'Apdex/ActionCable/TestChannel/test_action' => expected_values,
            'Apdex' => expected_values
          )
        end

        def test_sets_default_transaction_name_on_start
          @subscriber.start('perform_action.action_cable', :id, payload)
          assert_equal 'Controller/ActionCable/TestChannel/test_action', NewRelic::Agent::Transaction.tl_current.best_name
        ensure
          @subscriber.finish('perform_action.action_cable', :id, payload)
        end

        def test_sets_default_transaction_keeps_name_through_stop
          @subscriber.start('perform_action.action_cable', :id, payload)
          txn = NewRelic::Agent::Transaction.tl_current
          @subscriber.finish('perform_action.action_cable', :id, payload)
          assert_equal 'Controller/ActionCable/TestChannel/test_action', txn.best_name
        end

        def test_sets_transaction_name
          @subscriber.start('perform_action.action_cable', :id, payload)
          NewRelic::Agent.set_transaction_name('something/else')
          assert_equal 'Controller/ActionCable/something/else', NewRelic::Agent::Transaction.tl_current.best_name
        ensure
          @subscriber.finish('perform_action.action_cable', :id, payload)
        end

        def test_sets_transaction_name_holds_through_stop
          @subscriber.start('perform_action.action_cable', :id, payload)
          txn = NewRelic::Agent::Transaction.tl_current
          NewRelic::Agent.set_transaction_name('something/else')
          @subscriber.finish('perform_action.action_cable', :id, payload)
          assert_equal 'Controller/ActionCable/something/else', txn.best_name
        end

        def payload action='test_action'
          {:channel_class=>"TestChannel", :action=>action.to_sym, :data=>{"action"=>"#{action}"}}
        end
      end
    end
  end
end

end
