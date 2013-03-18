# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/instrumentation/rails4/action_controller'
require 'debugger'

class NewRelic::Agent::Instrumentation::ActionViewSubscriberTest < Test::Unit::TestCase
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
  end

  def teardown
    NewRelic::Agent.shutdown
    @stats_engine.clear_stats
  end

  def test_record_controller_metrics
    t0 = Time.now
    Time.stubs(:now).returns(t0, t0 + 2)

    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert_equal 1, @stats_engine.lookup_stats('Controller/test/index').call_count
    assert_equal 1, @stats_engine.lookup_stats('HttpDispatcher').call_count
    assert_equal 2.0, @stats_engine.lookup_stats('Controller/test/index').total_call_time
    assert_equal 2.0, @stats_engine.lookup_stats('HttpDispatcher').total_call_time
  end

  def test_record_apdex_metrics
    t0 = Time.now
    Time.stubs(:now).returns(t0, t0 + 1.5)

    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    apdex_metric = @stats_engine.lookup_stats('Apdex/test/index')
    apdex_rollup_metric = @stats_engine.lookup_stats('Apdex')
    assert_equal 0, apdex_metric.apdex_f
    assert_equal 0, apdex_rollup_metric.apdex_f
    assert_equal 1, apdex_metric.apdex_t
    assert_equal 1, apdex_rollup_metric.apdex_t
    assert_equal 0, apdex_metric.apdex_s
    assert_equal 0, apdex_rollup_metric.apdex_s
  end

  def test_record_error_metrics
    t0 = Time.now
    Time.stubs(:now).returns(t0, t0 + 2)

    @exit_payload.merge!(:exception => ['RuntimeError', 'some problem'])
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert_equal 1, @stats_engine.lookup_stats('Errors/Controller/test/index').call_count
    assert_equal 1, @stats_engine.lookup_stats('Errors/all').call_count
    assert_equal 2.0, @stats_engine.lookup_stats('Errors/Controller/test/index').total_call_time
    assert_equal 2.0, @stats_engine.lookup_stats('Errors/all').total_call_time
    assert_equal 1, @stats_engine.lookup_stats('Apdex').apdex_f
    assert_equal 1, @stats_engine.lookup_stats('Apdex/test/index').apdex_f
  end

  def test_records_scoped_metrics_for_evented_child_txn
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.start('process_action.action_controller', :id, @entry_payload \
                        .merge(:action => 'child', :path => '/child'))
    @subscriber.finish('process_action.action_controller', :id, @exit_payload \
                         .merge(:action => 'child', :path => '/child'))
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert_equal 1, @stats_engine.lookup_stats('Controller/test/child',
                                               'Controller/test/index').call_count
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

    assert_equal 1, @stats_engine.lookup_stats('Controller/test/child',
                                               'Controller/test/index').call_count
  end

  def test_record_nothing_for_ignored_action
    @entry_payload[:action] = 'ignored_action'
    @exit_payload[:action] = 'ignored_action'
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert_nil @stats_engine.lookup_stats('Controller/test/ignored_action')
    assert_nil @stats_engine.lookup_stats('Apdex/test/ignored_action')
    assert_nil @stats_engine.lookup_stats('Apdex')
    assert_nil @stats_engine.lookup_stats('HttpDispatcher')
  end

  def test_record_no_apdex_metric_for_ignored_apdex_action
    @entry_payload[:action] = 'ignored_apdex'
    @exit_payload[:action] = 'ignored_apdex'
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert @stats_engine.lookup_stats('Controller/test/ignored_apdex')
    assert_nil @stats_engine.lookup_stats('Apdex/test/ignored_apdex')
    assert_nil @stats_engine.lookup_stats('Apdex')
    assert @stats_engine.lookup_stats('HttpDispatcher')
  end

  def _test_ignore_end_user
  end

  def test_record_busy_time
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)
    NewRelic::Agent::BusyCalculator.harvest_busy

    assert_equal 1, @stats_engine.lookup_stats('Instance/Busy').call_count
  end

  def test_creates_transaction
    NewRelic::Agent.instance.transaction_sampler.reset!
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert_equal('Controller/test/index',
                 NewRelic::Agent.instance.transaction_sampler \
                   .last_sample.params[:path])
  end

  def _test_applies_txn_name_rules
  end

  def _test_records_filtered_request_params_in_txn
  end

  def _test_records_custom_parameters_in_txn
  end

  def _test_records_user_attributes_in_txn
  end

  def _test_records_referrer_in_txn
  end

  def _test_records_cpu_burn_in_txn
  end

  def _test_record_queue_time_metrics
  end
end if ::Rails::VERSION::MAJOR.to_i >= 4
