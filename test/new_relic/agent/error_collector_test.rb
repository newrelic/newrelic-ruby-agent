# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','data_container_tests'))
require 'new_relic/agent/internal_agent_error'

class NewRelic::Agent::ErrorCollectorTest < Minitest::Test
  def setup
    @test_config = {
      :capture_params => true,
      :disable_harvest_thread => true
    }
    NewRelic::Agent.config.add_config_for_testing(@test_config)

    @error_collector = NewRelic::Agent::ErrorCollector.new
    @error_collector.stubs(:enabled).returns(true)

    NewRelic::Agent::TransactionState.tl_clear_for_testing
    NewRelic::Agent.instance.stats_engine.reset!
  end

  def teardown
    super
    NewRelic::Agent::ErrorCollector.ignore_error_filter = nil
    NewRelic::Agent::TransactionState.tl_clear_for_testing
    NewRelic::Agent.config.reset_to_defaults
  end

  # Tests

  def test_empty
    @error_collector.notice_error(nil, :metric=> 'path')
    errors = harvest_error_traces
    assert_equal 0, errors.length
  end

  def test_drops_deprecated_options
    expects_logging(:warn, any_parameters)
    error = @error_collector.create_noticed_error(StandardError.new("message"),
                                  :referer => "lalalalala",
                                  :request => stub('request'),
                                  :request_params => {:x => 'y'})


    assert_empty error.attributes_from_notice_error
  end

  def test_exclude
    @error_collector.ignore(["IOError"])

    @error_collector.notice_error(IOError.new("message"), :metric => 'path')

    errors = harvest_error_traces

    assert_equal 0, errors.length
  end

  def test_exclude_later_config_changes
    @error_collector.notice_error(IOError.new("message"))

    NewRelic::Agent.config.add_config_for_testing(:'error_collector.ignore_errors' => "IOError")
    @error_collector.notice_error(IOError.new("message"))

    errors = harvest_error_traces

    assert_equal 1, errors.length
  end

  def test_exclude_block
    @error_collector.class.ignore_error_filter = wrapped_filter_proc

    @error_collector.notice_error(IOError.new("message"), :metric => 'path')
    @error_collector.notice_error(StandardError.new("message"), :metric => 'path')

    errors = harvest_error_traces

    assert_equal 1, errors.length
  end

  def test_failure_in_exclude_block
    @error_collector.class.ignore_error_filter = Proc.new do
      raise "HAHAHAHAH, error in the filter for ignoring errors!"
    end

    @error_collector.notice_error(StandardError.new("message"))

    errors = harvest_error_traces

    assert_equal 1, errors.length
  end

  def test_failure_block_assigned_with_different_instance
    @error_collector.class.ignore_error_filter = Proc.new do |*_|
      # meh, ignore 'em all!
      nil
    end

    new_error_collector = NewRelic::Agent::ErrorCollector.new
    new_error_collector.notice_error(StandardError.new("message"))

    assert_empty new_error_collector.error_trace_aggregator.harvest!
  end

  def test_increments_count_on_errors
    expects_error_count_increase(1) do
      @error_collector.notice_error(StandardError.new("Boo"))
    end
  end

  def test_increment_error_count_record_summary_and_txn_metric
    in_web_transaction('Controller/class/method') do
      @error_collector.increment_error_count!(NewRelic::Agent::TransactionState.tl_get, StandardError.new('Boo'))
    end

    assert_metrics_recorded(['Errors/all',
                             'Errors/allWeb',
                             'Errors/Controller/class/method'])
  end

  def test_increment_error_count_record_summary_and_txn_metric
    in_background_transaction('OtherTransaction/AnotherFramework/Job/perform') do
      @error_collector.increment_error_count!(NewRelic::Agent::TransactionState.tl_get, StandardError.new('Boo'))
    end

    assert_metrics_recorded(['Errors/all',
                             'Errors/allOther',
                             'Errors/OtherTransaction/AnotherFramework/Job/perform'])
  end

  def test_increment_error_count_summary_outside_transaction
    @error_collector.increment_error_count!(NewRelic::Agent::TransactionState.tl_get, StandardError.new('Boo'))

    assert_metrics_recorded(['Errors/all'])
    assert_metrics_not_recorded(['Errors/allWeb', 'Errors/allOther'])
  end

  def test_doesnt_increment_error_count_on_transaction_if_nameless
    @error_collector.increment_error_count!(NewRelic::Agent::TransactionState.tl_get,
                                            StandardError.new('Boo'),
                                            :metric => '(unknown)')

    assert_metrics_not_recorded(['Errors/(unknown)'])
  end


  class DifficultToDebugAgentError < NewRelic::Agent::InternalAgentError
  end

  class AnotherToughAgentError < NewRelic::Agent::InternalAgentError
  end

  def test_notices_agent_error
    @error_collector.notice_agent_error(DifficultToDebugAgentError.new)
    assert_equal 1, @error_collector.errors.size
  end

  def test_only_notices_agent_error_per_type
    @error_collector.notice_agent_error(DifficultToDebugAgentError.new)
    @error_collector.notice_agent_error(DifficultToDebugAgentError.new)

    assert_equal 1, @error_collector.errors.size
  end

  def test_only_notices_agent_error_per_type_allows_other_types
    @error_collector.notice_agent_error(DifficultToDebugAgentError.new)
    @error_collector.notice_agent_error(DifficultToDebugAgentError.new)
    @error_collector.notice_agent_error(AnotherToughAgentError.new)

    assert_equal 2, @error_collector.errors.size
  end

  def test_does_not_touch_error_metrics
    @error_collector.notice_agent_error(DifficultToDebugAgentError.new)
    @error_collector.notice_agent_error(DifficultToDebugAgentError.new)
    @error_collector.notice_agent_error(AnotherToughAgentError.new)

    assert_metrics_recorded_exclusive([])
  end

  def test_notice_agent_error_set_noticed_error_attributes
    @error_collector.notice_agent_error(DifficultToDebugAgentError.new)

    err = @error_collector.errors.first
    assert_equal "NewRelic/AgentError", err.path
    refute_nil err.stack_trace
  end

  def test_notice_agent_error_uses_exception_backtrace_if_present
    trace = ["boo", "yeah", "error"]
    exception = DifficultToDebugAgentError.new
    exception.set_backtrace(trace)
    @error_collector.notice_agent_error(exception)

    assert_equal trace, @error_collector.errors.first.stack_trace
  end

  def test_notice_agent_error_uses_caller_if_no_exception_backtrace
    exception = DifficultToDebugAgentError.new
    exception.set_backtrace(nil)
    @error_collector.notice_agent_error(exception)

    trace = @error_collector.errors.first.stack_trace
    assert trace.any? {|line| line.include?(__FILE__)}
  end

  def test_notice_agent_error_allows_an_error_past_queue_limit
    100.times { @error_collector.notice_error(StandardError.new("Ouch")) }

    exception = DifficultToDebugAgentError.new
    @error_collector.notice_agent_error(exception)

    assert_equal 21, @error_collector.errors.size
    assert_equal DifficultToDebugAgentError.name, @error_collector.errors.last.exception_class_name
  end

  def test_notice_agent_error_doesnt_clog_up_the_queue_limit
    exception = DifficultToDebugAgentError.new
    @error_collector.notice_agent_error(exception)

    100.times { @error_collector.notice_error(StandardError.new("Ouch")) }

    assert_equal 21, @error_collector.errors.size
  end

  def test_notice_agent_error_adds_support_message
    exception = DifficultToDebugAgentError.new("BOO")
    @error_collector.notice_agent_error(exception)

    err = @error_collector.errors.first
    assert err.message.include?(exception.message)
    assert err.message.include?("Ruby agent internal error")
  end

  def test_blamed_metric_from_options_outside_txn
    @error_collector.notice_error(StandardError.new('wut'), :metric => 'boo')
    assert_metrics_recorded(
      'Errors/boo' => { :call_count => 1}
    )
  end

  def test_blamed_metric_from_options_inside_txn
    in_transaction('Not/What/Youre/Looking/For') do
      @error_collector.notice_error(StandardError.new('wut'), :metric => 'boo')
    end
    assert_metrics_recorded_exclusive(
      {
        'Errors/all'      => { :call_count => 1 },
        'Errors/boo'      => { :call_count => 1 },
        'Errors/allOther' => { :call_count => 1 }
      },
      :filter => /^Errors\//
    )
  end

  def test_blamed_metric_from_transaction
    in_transaction('Controller/foo/bar') do
      @error_collector.notice_error(StandardError.new('wut'))
    end
    assert_metrics_recorded(
      'Errors/Controller/foo/bar' => { :call_count => 1 }
    )
  end

  def test_blamed_metric_with_no_transaction_and_no_options
    @error_collector.notice_error(StandardError.new('wut'))
    assert_metrics_recorded_exclusive(['Errors/all'])
  end

  def test_doesnt_double_count_same_exception
    in_transaction do
      error = StandardError.new('wat')
      @error_collector.notice_error(error)
      @error_collector.notice_error(error)
    end

    assert_metrics_recorded('Errors/all' => { :call_count => 1 })
    assert_equal 1, @error_collector.errors.length
  end

  def test_doesnt_count_seen_exceptions
    in_transaction do
      error = StandardError.new('wat')
      @error_collector.tag_exception(error)
      @error_collector.notice_error(error)
    end

    assert_metrics_not_recorded(['Errors/all'])
    assert_empty @error_collector.errors
  end

  def test_captures_attributes_on_notice_error
    error = StandardError.new('wat')
    attributes = Object.new
    @error_collector.notice_error(error, :attributes => attributes)

    noticed = @error_collector.errors.first
    assert_equal attributes, noticed.attributes
  end

  module Winner
    def winner
      'yay'
    end
  end

  def test_sense_method
    object = Object.new
    object.extend(Winner)
    assert_equal nil,   @error_collector.sense_method(object, 'blab')
    assert_equal 'yay', @error_collector.sense_method(object, 'winner')
  end

  def test_extract_stack_trace
    exception = mock('exception', :original_exception => nil,
                                  :backtrace => nil)

    assert_equal('<no stack trace>', @error_collector.extract_stack_trace(exception))
  end

  def test_extract_stack_trace_positive
    orig = mock('original', :backtrace => "STACK STACK STACK")
    exception = mock('exception', :original_exception => orig)

    assert_equal('STACK STACK STACK', @error_collector.extract_stack_trace(exception))
  end

  def test_skip_notice_error_is_true_if_the_error_collector_is_disabled
    error = StandardError.new
    with_config(:'error_collector.enabled' => false) do
      assert @error_collector.skip_notice_error?(error)
    end
  end

  def test_skip_notice_error_is_true_if_the_error_is_nil
    error = nil
    with_config(:'error_collector.enabled' => true) do
      @error_collector.expects(:error_is_ignored?).with(error).returns(false)
      assert @error_collector.skip_notice_error?(error)
    end
  end

  def test_skip_notice_error_is_true_if_the_error_is_ignored
    error = StandardError.new
    with_config(:'error_collector.enabled' => true) do
      @error_collector.expects(:error_is_ignored?).with(error).returns(true)
      assert @error_collector.skip_notice_error?(error)
    end
  end

  def test_skip_notice_error_returns_false_for_non_nil_unignored_errors_with_an_enabled_error_collector
    error = StandardError.new
    with_config(:'error_collector.enabled' => true) do
      @error_collector.expects(:error_is_ignored?).with(error).returns(false)
      refute @error_collector.skip_notice_error?(error)
    end
  end

  class ::AnError
  end

  def test_filtered_error_positive
    with_config(:'error_collector.ignore_errors' => 'AnError') do
      error = AnError.new
      assert @error_collector.filtered_error?(error)
    end
  end

  def test_filtered_error_negative
    error = AnError.new
    refute @error_collector.filtered_error?(error)
  end

  def test_filtered_by_error_filter_empty
    # should return right away when there's no filter
    refute @error_collector.filtered_by_error_filter?(nil)
  end

  def test_filtered_by_error_filter_positive
    saw_error = nil
    NewRelic::Agent::ErrorCollector.ignore_error_filter = Proc.new do |e|
      saw_error = e
      false
    end

    error = StandardError.new
    assert @error_collector.filtered_by_error_filter?(error)

    assert_equal error, saw_error
  end

  def test_filtered_by_error_filter_negative
    saw_error = nil
    NewRelic::Agent::ErrorCollector.ignore_error_filter = Proc.new do |e|
      saw_error = e
      true
    end

    error = StandardError.new
    refute @error_collector.filtered_by_error_filter?(error)

    assert_equal error, saw_error
  end

  def test_error_is_ignored_no_error
    refute @error_collector.error_is_ignored?(nil)
  end

  def test_does_not_tag_frozen_errors
    e = StandardError.new
    e.freeze
    @error_collector.notice_error(e)
    refute @error_collector.exception_tagged?(e)
  end

  def test_handles_failures_during_error_tagging
    e = StandardError.new
    e.stubs(:instance_variable_set).raises(RuntimeError)
    expects_logging(:warn, any_parameters)

    @error_collector.notice_error(e)
  end

  if NewRelic::LanguageSupport.jruby?
    def test_does_not_tag_java_objects
      e = java.lang.String.new
      @error_collector.notice_error(e)
      refute @error_collector.exception_tagged?(e)
    end
  end

  private

  def expects_error_count_increase(increase)
    count = get_error_stats
    yield
    assert_equal increase, get_error_stats - count
  end

  def get_error_stats
    NewRelic::Agent.get_stats("Errors/all").call_count
  end

  def wrapped_filter_proc
    Proc.new do |e|
      if e.is_a? IOError
        return nil
      else
        return e
      end
    end
  end

  def silence_stream(*args)
    super
  rescue NoMethodError
    yield
  end

  def harvest_error_traces
    @error_collector.error_trace_aggregator.harvest!
  end
end
