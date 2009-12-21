require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper')) 

class TaskInstrumentationTest < Test::Unit::TestCase
  include NewRelic::Agent::Instrumentation::ControllerInstrumentation
  attr_accessor :agent
  def setup
    super
    NewRelic::Agent.manual_start
    @agent = NewRelic::Agent.instance
    @agent.transaction_sampler.send :reset_builder
    @agent.transaction_sampler.reset!
    @agent.stats_engine.clear_stats
  end
  def teardown
    NewRelic::Agent.shutdown
    super
  end
  
  def test_run
    run_task_inner 0
    stat_names = %w[Controller/TaskInstrumentationTest/inner_task_0
                    Controller HttpDispatcher
                    Apdex Apdex/TaskInstrumentationTest/inner_task_0].sort
    expected_but_missing = stat_names - @agent.stats_engine.metrics
    assert_equal 0, expected_but_missing.size, @agent.stats_engine.metrics.map  { |n|
      stat = @agent.stats_engine.get_stats(n)
      "#{'%-26s' % n}: #{stat.call_count} calls @ #{stat.average_call_time} sec/call"
    }.join("\n  ") + "\nmissing: #{expected_but_missing.inspect}"
    assert_equal 1, @agent.stats_engine.get_stats_no_scope('Controller').call_count
    assert_equal 1, @agent.stats_engine.get_stats('Controller/TaskInstrumentationTest/inner_task_0').call_count
  end
  
  def test_run_recursive
    run_task_inner(3)
    assert_equal 1, @agent.stats_engine.get_stats('Controller/TaskInstrumentationTest/inner_task_3').call_count
    assert_equal 1, @agent.stats_engine.get_stats('Controller/TaskInstrumentationTest/inner_task_2').call_count
    assert_equal 1, @agent.stats_engine.get_stats('Controller/TaskInstrumentationTest/inner_task_0').call_count
    assert_equal 4, @agent.stats_engine.get_stats('Controller').call_count
  end
  
  def test_run_nested
    run_task_outer(3)
    @agent.stats_engine.metrics.sort.each do |n|
      stat = @agent.stats_engine.get_stats(n)
      #      puts "#{'%-26s' % n}: #{stat.call_count} calls @ #{stat.average_call_time} sec/call"
    end
    assert_equal 1, @agent.stats_engine.get_stats('Controller/TaskInstrumentationTest/outer_task').call_count
    assert_equal 2, @agent.stats_engine.get_stats('Controller/TaskInstrumentationTest/inner_task_0').call_count
    assert_equal 9, @agent.stats_engine.get_stats('Controller').call_count
  end
  
  def test_reentrancy
    run_task_inner(1)
    assert_equal 1, @agent.stats_engine.get_stats('Controller/TaskInstrumentationTest/inner_task_0').call_count
    assert_equal 1, @agent.stats_engine.get_stats('Controller/TaskInstrumentationTest/inner_task_1').call_count
  end
  
  def test_transaction
    assert_equal 0, @agent.transaction_sampler.scope_depth, "existing unfinished sample"
    assert_nil @agent.transaction_sampler.last_sample
    assert_equal @agent.transaction_sampler, @agent.stats_engine.instance_variable_get("@transaction_sampler")
    run_task_outer(10)
    @agent.stats_engine.metrics.sort.each do |n|
      stat = @agent.stats_engine.get_stats_no_scope(n)
      #      puts "#{'%-26s' % n}: #{stat.call_count} calls @ #{stat.average_call_time} sec/call"
    end
    assert_equal 1, @agent.stats_engine.get_stats('Controller/TaskInstrumentationTest/outer_task').call_count
    assert_equal 23, @agent.stats_engine.get_stats('Controller').call_count
    assert_equal 2, @agent.stats_engine.get_stats('Controller/TaskInstrumentationTest/inner_task_0').call_count
    assert_equal 0, @agent.transaction_sampler.scope_depth, "existing unfinished sample"
    sample = @agent.transaction_sampler.last_sample
    assert_not_nil sample
    assert_not_nil sample.params[:cpu_time], "cpu time nil: \n#{sample}"
    assert sample.params[:cpu_time] >= 0, "cpu time: #{sample.params[:cpu_time]},\n#{sample}"
    assert_equal '10', sample.params[:request_params][:level]
  end
  
  def test_block
    assert_equal @agent, NewRelic::Agent.instance
    @acct = 'Redrocks'
    perform_action_with_newrelic_trace(:name => 'hello', :force => true, :params => { :account => @acct}) do
      Rails.logger.info "Hello world"
    end
    @agent.stats_engine.metrics.sort.each do |n|
      stat = @agent.stats_engine.get_stats_no_scope(n)
      #puts "#{'%-26s' % n}: #{stat.call_count} calls @ #{stat.average_call_time} sec/call"
    end
    assert_equal @agent, NewRelic::Agent.instance
    assert_equal 1, @agent.stats_engine.get_stats_no_scope('Controller/TaskInstrumentationTest/hello').call_count
    sample = @agent.transaction_sampler.last_sample
    assert_not_nil sample
    assert_equal 'Redrocks', sample.params[:request_params][:account]
    
  end
  
  def test_error_handling
    @agent.error_collector.harvest_errors([])
    assert_raise RuntimeError do
      run_task_exception
    end
    errors = @agent.error_collector.harvest_errors([])
    assert_equal 1, errors.size
  end
  
  private
  
  def run_task_inner(n)
    sleep 0.1
    return if n == 0
    run_task_inner(n-1)
  end
  
  def run_task_outer(n=0)
    run_task_inner(n)
    run_task_inner(n)
  end
  
  def run_task_exception
    raise "This is an error"
  end
  
  add_transaction_tracer :run_task_exception
  add_transaction_tracer :run_task_inner, :name => 'inner_task_#{args[0]}'
  add_transaction_tracer :run_task_outer, :name => 'outer_task', :params => '{ :level => args[0] }'
end
