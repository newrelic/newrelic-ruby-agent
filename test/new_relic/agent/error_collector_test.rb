# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','data_container_tests'))
require 'new_relic/agent/internal_agent_error'

class NewRelic::Agent::ErrorCollectorTest < Minitest::Test
  def setup
    @test_config = { :capture_params => true }
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

  # Helpers for DataContainerTests

  def create_container
    NewRelic::Agent::ErrorCollector.new
  end

  def populate_container(collector, n)
    n.times do |i|
      collector.notice_error('yay errors', :metric => 'path')
    end
  end

  include NewRelic::DataContainerTests

  # Tests

  def test_empty
    @error_collector.harvest!
    @error_collector.notice_error(nil, :metric=> 'path', :request_params => {:x => 'y'})
    errors = @error_collector.harvest!

    assert_equal 0, errors.length

    @error_collector.notice_error('Some error message', :metric=> 'path', :request_params => {:x => 'y'})
    errors = @error_collector.harvest!

    err = errors.first
    assert_equal 'Some error message', err.message
    assert_equal 'y', err.params[:request_params][:x]
    assert_equal '', err.params[:request_uri]
    assert_equal '', err.params[:request_referer]
    assert_equal 'path', err.path
    assert_equal 'Error', err.exception_class_name
  end

  def test_simple
    @error_collector.notice_error(StandardError.new("message"), :uri => '/myurl/', :metric => 'path', :referer => 'test_referer', :request_params => {:x => 'y'})

    errors = @error_collector.harvest!

    assert_equal errors.length, 1

    err = errors.first
    assert_equal 'message', err.message
    assert_equal 'y', err.params[:request_params][:x]
    assert_equal '/myurl/', err.params[:request_uri]
    assert_equal 'test_referer', err.params[:request_referer]
    assert_equal 'path', err.path
    assert_equal 'StandardError', err.exception_class_name

    # the collector should now return an empty array since nothing
    # has been added since its last harvest
    errors = @error_collector.harvest!
    assert errors.length == 0
  end

  def test_long_message
    #yes, times 500. it's a 5000 byte string. Assuming strings are
    #still 1 byte / char.
    @error_collector.notice_error(StandardError.new("1234567890" * 500), :uri => '/myurl/', :metric => 'path', :request_params => {:x => 'y'})

    errors = @error_collector.harvest!

    assert_equal errors.length, 1

    err = errors.first
    assert_equal 4096, err.message.length
    assert_equal ('1234567890' * 500)[0..4095], err.message
  end

  def test_collect_failover
    @error_collector.notice_error(StandardError.new("message"), :metric => 'first', :request_params => {:x => 'y'})

    errors = @error_collector.harvest!

    @error_collector.notice_error(StandardError.new("message"), :metric => 'second', :request_params => {:x => 'y'})
    @error_collector.notice_error(StandardError.new("message"), :metric => 'path', :request_params => {:x => 'y'})
    @error_collector.notice_error(StandardError.new("message"), :metric => 'last', :request_params => {:x => 'y'})

    @error_collector.merge!(errors)
    errors = @error_collector.harvest!

    assert_equal 4, errors.length
    assert_equal_unordered(%w(first second path last), errors.map { |e| e.path })

    @error_collector.notice_error(StandardError.new("message"), :metric => 'first', :request_params => {:x => 'y'})
    @error_collector.notice_error(StandardError.new("message"), :metric => 'last', :request_params => {:x => 'y'})

    errors = @error_collector.harvest!
    assert_equal 2, errors.length
    assert_equal 'first', errors.first.path
    assert_equal 'last', errors.last.path
  end

  def test_queue_overflow

    max_q_length = 20     # for some reason I can't read the constant in ErrorCollector

    silence_stream(::STDOUT) do
     (max_q_length + 5).times do |n|
        @error_collector.notice_error(StandardError.new("exception #{n}"), :metric => "path", :request_params => {:x => n})
      end
    end

    errors = @error_collector.harvest!
    assert errors.length == max_q_length
    errors.each_index do |i|
      err = errors.shift
      assert_equal i.to_s, err.params[:request_params][:x], err.params.inspect
    end
  end

  # Why would anyone undef these methods?
  class TestClass
    undef to_s
    undef inspect
  end


  def test_supported_param_types
    types = [[1, '1'],
    [1.1, '1.1'],
    ['hi', 'hi'],
    [:hi, :hi],
    [StandardError.new("test"), "#<StandardError>"],
    [TestClass.new, "#<NewRelic::Agent::ErrorCollectorTest::TestClass>"]
    ]

    types.each do |test|
      @error_collector.notice_error(StandardError.new("message"), :metric => 'path',
                                    :request_params => {:x => test[0]})
      assert_equal test[1], @error_collector.harvest![0].params[:request_params][:x]
    end
  end


  def test_exclude
    @error_collector.ignore(["IOError"])

    @error_collector.notice_error(IOError.new("message"), :metric => 'path', :request_params => {:x => 'y'})

    errors = @error_collector.harvest!

    assert_equal 0, errors.length
  end

  def test_exclude_later_config_changes
    @error_collector.notice_error(IOError.new("message"))

    NewRelic::Agent.config.add_config_for_testing(:'error_collector.ignore_errors' => "IOError")
    @error_collector.notice_error(IOError.new("message"))

    errors = @error_collector.harvest!

    assert_equal 1, errors.length

  end

  def test_exclude_block
    @error_collector.class.ignore_error_filter = wrapped_filter_proc

    @error_collector.notice_error(IOError.new("message"), :metric => 'path', :request_params => {:x => 'y'})
    @error_collector.notice_error(StandardError.new("message"), :metric => 'path', :request_params => {:x => 'y'})

    errors = @error_collector.harvest!

    assert_equal 1, errors.length
  end

  def test_failure_in_exclude_block
    @error_collector.class.ignore_error_filter = Proc.new do
      raise "HAHAHAHAH, error in the filter for ignoring errors!"
    end

    @error_collector.notice_error(StandardError.new("message"))

    errors = @error_collector.harvest!

    assert_equal 1, errors.length
  end

  def test_failure_block_assigned_with_different_instance
    @error_collector.class.ignore_error_filter = Proc.new do |*_|
      # meh, ignore 'em all!
      nil
    end

    new_error_collector = NewRelic::Agent::ErrorCollector.new
    new_error_collector.notice_error(StandardError.new("message"))

    assert_empty new_error_collector.harvest!
  end

  def test_obfuscates_error_messages_when_high_security_is_set
    with_config(:high_security => true) do
      @error_collector.notice_error(StandardError.new("YO SQL BAD: serect * flom test where foo = 'bar'"))
      @error_collector.notice_error(StandardError.new("YO SQL BAD: serect * flom test where foo in (1,2,3,4,5)"))

      errors = @error_collector.harvest!

      assert_equal(NewRelic::NoticedError::STRIPPED_EXCEPTION_REPLACEMENT_MESSAGE, errors[0].message)
      assert_equal(NewRelic::NoticedError::STRIPPED_EXCEPTION_REPLACEMENT_MESSAGE, errors[1].message)
    end
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

  def test_icrement_error_count_summary_outside_transaction
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
    assert_kind_of Hash, err.params
    refute_nil err.params[:stack_trace]
  end

  def test_notice_agent_error_uses_exception_backtrace_if_present
    trace = ["boo", "yeah", "error"]
    exception = DifficultToDebugAgentError.new
    exception.set_backtrace(trace)
    @error_collector.notice_agent_error(exception)

    assert_equal trace, @error_collector.errors.first.params[:stack_trace]
  end

  def test_notice_agent_error_uses_caller_if_no_exception_backtrace
    exception = DifficultToDebugAgentError.new
    exception.set_backtrace(nil)
    @error_collector.notice_agent_error(exception)

    trace = @error_collector.errors.first.params[:stack_trace]
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
      @error_collector.tag_as_seen(NewRelic::Agent::TransactionState.tl_get, error)
      @error_collector.notice_error(error)
    end

    assert_metrics_not_recorded(['Errors/all'])
    assert_empty @error_collector.errors
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
end
