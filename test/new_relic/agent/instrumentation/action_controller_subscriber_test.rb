# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

if defined?(::Rails)

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/instrumentation/action_controller_subscriber'

class NewRelic::Agent::Instrumentation::ActionControllerSubscriberTest < Minitest::Test
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
    freeze_time
    @subscriber = NewRelic::Agent::Instrumentation::ActionControllerSubscriber.new
    NewRelic::Agent.drop_buffered_data
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
    NewRelic::Agent::TransactionState.tl_clear_for_testing
  end

  def teardown
    NewRelic::Agent.shutdown
    @stats_engine.clear_stats
  end

  def test_record_controller_metrics
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
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    advance_time(1.5)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    expected_values = { :apdex_f => 0, :apdex_t => 1, :apdex_s => 0 }
    assert_metrics_recorded(
      'Apdex/test/index' => expected_values,
      'Apdex' => expected_values
    )
  end

  def test_record_apdex_metrics_with_error
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    advance_time(1.5)

    error = StandardError.new("boo")
    @exit_payload[:exception] = error
    NewRelic::Agent.notice_error(error)

    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    expected_values = { :apdex_f => 1, :apdex_t => 0, :apdex_s => 0 }
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
      ['Nested/Controller/test/child', 'Controller/test/child'] => { :call_count => 1 }
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
      ['Nested/Controller/test/child', 'Controller/test/child'] => { :call_count => 1 }
    )
  end

  def test_sets_default_transaction_name_on_start
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    assert_equal 'Controller/test/index', NewRelic::Agent::Transaction.tl_current.best_name
  ensure
    @subscriber.finish('process_action.action_controller', :id, @entry_payload)
  end

  def test_sets_default_transaction_keeps_name_through_stop
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    txn = NewRelic::Agent::Transaction.tl_current
    @subscriber.finish('process_action.action_controller', :id, @entry_payload)
    assert_equal 'Controller/test/index', txn.best_name
  end

  def test_sets_transaction_name
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    NewRelic::Agent.set_transaction_name('something/else')
    assert_equal 'Controller/something/else', NewRelic::Agent::Transaction.tl_current.best_name
  ensure
    @subscriber.finish('process_action.action_controller', :id, @entry_payload)
  end

  def test_sets_transaction_name_holds_through_stop
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    txn = NewRelic::Agent::Transaction.tl_current
    NewRelic::Agent.set_transaction_name('something/else')
    @subscriber.finish('process_action.action_controller', :id, @entry_payload)
    assert_equal 'Controller/something/else', txn.best_name
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
    txn = NewRelic::Agent::Transaction.tl_current
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert txn.ignore_enduser?
  end

  def test_record_busy_time
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    advance_time(1)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)
    NewRelic::Agent::BusyCalculator.harvest_busy

    assert_metrics_recorded('Instance/Busy' => { :call_count => 1, :total_call_time => 1.0 })
  end

  def test_creates_transaction
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert_equal('Controller/test/index',
                 NewRelic::Agent.instance.transaction_sampler \
                   .last_sample.transaction_name)
    assert_equal('Controller/test/index',
                 NewRelic::Agent.instance.transaction_sampler \
                   .last_sample.root_node.called_nodes[0].metric_name)
  end

  def test_applies_txn_name_rules
    rule_specs = [{'match_expression' => 'test', 'replacement' => 'taste'}]

    with_transaction_renaming_rules(rule_specs) do
      @subscriber.start('process_action.action_controller', :id, @entry_payload)
      @subscriber.finish('process_action.action_controller', :id, @exit_payload)
    end

    assert_metrics_recorded(['Controller/taste/index'])
    assert_metrics_not_recorded(['Controller/test/index'])
  end

  def test_record_queue_time_metrics
    app = lambda do |env|
      @subscriber.start('process_action.action_controller', :id, @entry_payload)
      advance_time(2)
      @subscriber.finish('process_action.action_controller', :id, @exit_payload)
    end

    t0 = Time.now
    env = { 'HTTP_X_REQUEST_START' => (t0 - 5).to_f.to_s }
    ::NewRelic::Rack::AgentHooks.new(app).call(env)

    assert_metrics_recorded(
      'WebFrontend/QueueTime' => {
        :call_count => 1,
        :total_call_time => 5.0
      }
    )
  end

  def test_dont_record_queue_time_if_no_header
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert_metrics_not_recorded('WebFrontend/QueueTime')
  end

  def test_dont_record_queue_time_in_nested_transaction
    app = lambda do |env|
      @subscriber.start('process_action.action_controller',  :id, @entry_payload)
      @subscriber.start('process_action.action_controller',  :id, @entry_payload)
      @subscriber.finish('process_action.action_controller', :id, @exit_payload)
      @subscriber.finish('process_action.action_controller', :id, @exit_payload)
    end

    t0 = Time.now
    env = { 'HTTP_X_REQUEST_START' => (t0 - 5).to_f.to_s }
    ::NewRelic::Rack::AgentHooks.new(app).call(env)

    assert_metrics_recorded(
      'WebFrontend/QueueTime' => {
        :call_count => 1,
        :total_call_time => 5.0
      }
    )
  end

  def test_records_request_params_in_txn
    with_config(:capture_params => true) do
      @entry_payload[:params]['number'] = '666'
      @subscriber.start('process_action.action_controller', :id, @entry_payload)
      @subscriber.finish('process_action.action_controller', :id, @exit_payload)
    end

    sample = NewRelic::Agent.instance.transaction_sampler.last_sample
    assert_equal('666', attributes_for(sample, :agent)['request.parameters.number'])
  end

  def test_records_filtered_request_params_in_txn
    with_config(:capture_params => true) do
      @entry_payload[:params]['password'] = 'secret'
      @subscriber.start('process_action.action_controller', :id, @entry_payload)
      @subscriber.finish('process_action.action_controller', :id, @exit_payload)
    end

    sample = NewRelic::Agent.instance.transaction_sampler.last_sample
    assert_equal('[FILTERED]', attributes_for(sample, :agent)['request.parameters.password'])
  end

  def test_records_custom_parameters_in_txn
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    NewRelic::Agent.add_custom_attributes('number' => '666')
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    sample = NewRelic::Agent.instance.transaction_sampler.last_sample
    assert_equal('666', attributes_for(sample, :custom)['number'])
  end
end if ::Rails::VERSION::MAJOR.to_i >= 4

else
  puts "Skipping tests in #{__FILE__} because Rails is unavailable"
end
