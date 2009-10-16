require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper')) 
require 'action_controller/base'

class TaskInstrumentationTest < Test::Unit::TestCase
  include NewRelic::Agent::Instrumentation::ControllerInstrumentation
  attr_accessor :agent
  def setup
    super
    NewRelic::Agent.manual_start
    @agent = NewRelic::Agent.instance
  end
  def teardown
    @agent.stats_engine.clear_stats
    NewRelic::Agent.shutdown
    super
  end
  
  def test_run
    run_task_inner 0
    stat_names = %w[Controller/TaskInstrumentationTest/inner_task_0
                    ActiveRecord/all Controller HttpDispatcher
                    Apdex Apdex/TaskInstrumentationTest/inner_task_0].sort
    expected_but_missing = stat_names - @agent.stats_engine.metrics
    assert_equal 0, expected_but_missing.size, expected_but_missing.inspect
    @agent.stats_engine.metrics.each do |n|
      stat = @agent.stats_engine.get_stats(n)
#      puts "#{'%-26s' % n}: #{stat.call_count} calls @ #{stat.average_call_time} sec/call"
    end
    assert_equal 1, @agent.stats_engine.get_stats_no_scope('Controller').call_count
    assert_equal 1, @agent.stats_engine.get_stats('Controller/TaskInstrumentationTest/inner_task_0').call_count
  end

  def test_run_recursive
    run_task_inner(3)
    assert_equal 0, @agent.stats_engine.get_stats('Controller/TaskInstrumentationTest/inner_task_3').call_count
    assert_equal 0, @agent.stats_engine.get_stats('Controller/TaskInstrumentationTest/inner_task_2').call_count
    assert_equal 1, @agent.stats_engine.get_stats('Controller/TaskInstrumentationTest/inner_task_0').call_count
    assert_equal 1, @agent.stats_engine.get_stats('Controller').call_count
  end
  
  def test_run_nested
    run_task_outer(3)
    @agent.stats_engine.metrics.sort.each do |n|
      stat = @agent.stats_engine.get_stats(n)
#      puts "#{'%-26s' % n}: #{stat.call_count} calls @ #{stat.average_call_time} sec/call"
    end
    assert_equal 0, @agent.stats_engine.get_stats('Controller/TaskInstrumentationTest/outer_task').call_count
    assert_equal 2, @agent.stats_engine.get_stats('Controller').call_count
    assert_equal 2, @agent.stats_engine.get_stats('Controller/TaskInstrumentationTest/inner_task_0').call_count
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
  
  add_transaction_tracer :run_task_inner, :name => 'inner_task_#{args[0]}'
  add_transaction_tracer :run_task_outer, :name => 'outer_task'
end
