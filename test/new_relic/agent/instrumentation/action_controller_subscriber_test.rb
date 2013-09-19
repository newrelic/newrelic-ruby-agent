# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

if defined?(::Rails)

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/instrumentation/action_controller_subscriber'

class NewRelic::Agent::Instrumentation::ActionControllerSubscriberTest < Test::Unit::TestCase
  class TestController
    include NewRelic::Agent::Instrumentation::ControllerInstrumentation

    def self.controller_path
      'test'
    end

    def action_name
      'test'
    end

    newrelic_ignore :only => :ignored_action
    newrelic_ignore_apdex :only => :ignored_apdex
    newrelic_ignore_enduser :only => :ignored_enduser
  end

  def setup
    @subscriber = NewRelic::Agent::Instrumentation::ActionControllerSubscriber.new
    NewRelic::Agent.instance.stats_engine.clear_stats
    @entry_payload = {
      :controller => TestController.to_s,
      :action => 'index',
      :format => :html,
      :method => 'GET',
      :path => '/tests',
      :params => { :controller => 'test_controller', :action => 'index' },
    }
    @exit_payload = @entry_payload.merge(:status => 200, :view_runtime => 5.0,
                                         :db_runtime => 0.5 )
    @stats_engine = NewRelic::Agent.instance.stats_engine
    @stats_engine.clear_stats
    NewRelic::Agent.manual_start
    NewRelic::Agent::TransactionState.clear
  end

  def teardown
    NewRelic::Agent.shutdown
    @stats_engine.clear_stats
  end

  def test_record_controller_metrics
    freeze_time
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    advance_time(2)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    expected_values = { :call_count => 1, :total_call_time => 2.0 }
    assert_metrics_recorded(
      'Controller/test/index' => expected_values,
      'HttpDispatcher' => expected_values
    )
  end

  def test_record_apdex_metrics
    freeze_time
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    advance_time(1.5)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    expected_values = { :apdex_f => 0, :apdex_t => 1, :apdex_s => 0 }
    assert_metrics_recorded(
      'Apdex/test/index' => expected_values,
      'Apdex' => expected_values
    )
  end

  def test_records_scoped_metrics_for_evented_child_txn
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.start('process_action.action_controller', :id, @entry_payload \
                        .merge(:action => 'child', :path => '/child'))
    @subscriber.finish('process_action.action_controller', :id, @exit_payload \
                         .merge(:action => 'child', :path => '/child'))
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert_metrics_recorded(
      ['Controller/test/child', 'Controller/test/index'] => { :call_count => 1 }
    )
  end

  def test_records_scoped_metrics_for_traced_child_txn
    controller = TestController.new
    controller.perform_action_with_newrelic_trace(:category => :controller,
                                                  :name => 'index',
                                                  :class_name => 'test') do
      @subscriber.start('process_action.action_controller', :id, @entry_payload \
                          .merge(:action => 'child', :path => '/child'))
      @subscriber.finish('process_action.action_controller', :id, @exit_payload \
                           .merge(:action => 'child', :path => '/child'))
    end

    assert_metrics_recorded(
      ['Controller/test/child', 'Controller/test/index'] => { :call_count => 1 }
    )
  end

  def test_sets_default_transaction_name_on_start
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    assert_equal 'Controller/test/index', NewRelic::Agent::Transaction.current.name
  ensure
    @subscriber.finish('process_action.action_controller', :id, @entry_payload)
  end

  def test_sets_default_transaction_keeps_name_through_stop
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    txn = NewRelic::Agent::Transaction.current
    @subscriber.finish('process_action.action_controller', :id, @entry_payload)
    assert_equal 'Controller/test/index', txn.name
  end

  def test_sets_transaction_name
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    NewRelic::Agent.set_transaction_name('something/else')
    assert_equal 'Controller/something/else', NewRelic::Agent::Transaction.current.name
  ensure
    @subscriber.finish('process_action.action_controller', :id, @entry_payload)
  end

  def test_sets_transaction_name_holds_through_stop
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    txn = NewRelic::Agent::Transaction.current
    NewRelic::Agent.set_transaction_name('something/else')
    @subscriber.finish('process_action.action_controller', :id, @entry_payload)
    assert_equal 'Controller/something/else', txn.name
  end

  def test_record_nothing_for_ignored_action
    @entry_payload[:action] = 'ignored_action'
    @exit_payload[:action] = 'ignored_action'
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert_metrics_not_recorded([
      'Controller/test/ignored_action',
      'Apdex/test/ignored_action',
      'Apdex',
      'HttpDispatcher'
    ])
  end

  def test_record_no_apdex_metric_for_ignored_apdex_action
    @entry_payload[:action] = 'ignored_apdex'
    @exit_payload[:action] = 'ignored_apdex'
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert_metrics_recorded(['Controller/test/ignored_apdex', 'HttpDispatcher'])
    assert_metrics_not_recorded(['Apdex', 'Apdex/test/ignored_apdex'])
  end

  def test_ignore_end_user
    @entry_payload[:action] = 'ignored_enduser'
    @exit_payload[:action] = 'ignored_enduser'
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert NewRelic::Agent::TransactionState.get.request_ignore_enduser
  end

  def test_record_busy_time
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)
    NewRelic::Agent::BusyCalculator.harvest_busy

    assert_metrics_recorded('Instance/Busy' => { :call_count => 1 })
  end

  def test_creates_transaction
    NewRelic::Agent.instance.transaction_sampler.reset!
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert_equal('Controller/test/index',
                 NewRelic::Agent.instance.transaction_sampler \
                   .last_sample.params[:path])
    assert_equal('Controller/test/index',
                 NewRelic::Agent.instance.transaction_sampler \
                   .last_sample.root_segment.called_segments[0].metric_name)
  end

  def test_applies_txn_name_rules
    rule = NewRelic::Agent::RulesEngine::Rule.new('match_expression' => 'test',
                                                  'replacement'      => 'taste')
    NewRelic::Agent.instance.transaction_rules << rule
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert NewRelic::Agent.instance.stats_engine \
      .lookup_stats('Controller/taste/index')
    assert_nil NewRelic::Agent.instance.stats_engine \
      .lookup_stats('Controller/test/index')
  ensure
    NewRelic::Agent.instance.instance_variable_set(:@transaction_rules,
                                             NewRelic::Agent::RulesEngine.new)
  end

  def test_record_queue_time_metrics
    t0 = Time.now
    Time.stubs(:now).returns(t0)
    env = { 'HTTP_X_REQUEST_START' => (t0 - 5).to_f.to_s }
    NewRelic::Agent.instance.events.notify(:before_call, env)

    Time.stubs(:now).returns(t0, t0 + 2)
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    metric = @stats_engine.lookup_stats('WebFrontend/QueueTime')
    assert_equal 1, metric.call_count
    assert_in_delta(5.0, metric.total_call_time, 0.1)
  end

  def test_dont_record_queue_time_if_no_header
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert_nil @stats_engine.lookup_stats('WebFrontend/QueueTime')
  end

  def test_records_request_params_in_txn
    NewRelic::Agent.instance.transaction_sampler.reset!
    @entry_payload[:params]['number'] = '666'
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert_equal('666',
                 NewRelic::Agent.instance.transaction_sampler \
                   .last_sample.params[:request_params]['number'])
  end

  def test_records_filtered_request_params_in_txn
    NewRelic::Agent.instance.transaction_sampler.reset!
    @entry_payload[:params]['password'] = 'secret'
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert_equal('[FILTERED]',
                 NewRelic::Agent.instance.transaction_sampler \
                   .last_sample.params[:request_params]['password'])
  end

  def test_records_custom_parameters_in_txn
    NewRelic::Agent.instance.transaction_sampler.reset!
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    NewRelic::Agent.add_custom_parameters('number' => '666')
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert_equal('666',
                 NewRelic::Agent.instance.transaction_sampler \
                   .last_sample.params[:custom_params]['number'])
  end
end if ::Rails::VERSION::MAJOR.to_i >= 4

else
  puts "Skipping tests in #{__FILE__} because Rails is unavailable"
end
