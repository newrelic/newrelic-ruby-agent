# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

MIN_RAILS_VERSION = 5

if defined?(::Rails) && ::Rails::VERSION::MAJOR.to_i >= MIN_RAILS_VERSION

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

        def test_creates_transaction
          @subscriber.start('perform_action.action_cable', :id, payload)
          @subscriber.finish('perform_action.action_cable', :id, payload)

          assert_equal('Controller/ActionCable/TestChannel/test_action',
                       NewRelic::Agent.instance.transaction_sampler.last_sample.transaction_name)
          assert_equal('Controller/ActionCable/TestChannel/test_action',
                       NewRelic::Agent.instance.transaction_sampler.last_sample.root_node.called_nodes[0].metric_name)
        end

        def payload action='test_action'
          {:channel_class=>"TestChannel", :action=>action.to_sym, :data=>{"action"=>"#{action}"}}
        end
      end
    end
  end
end

end
