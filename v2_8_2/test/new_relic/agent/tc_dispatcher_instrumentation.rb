require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper')) 

class NewRelic::Agent::DispatcherInstrumentationTests < Test::Unit::TestCase
  
  class FunnyDispatcher
    include NewRelic::Agent::Instrumentation::DispatcherInstrumentation
  end
  def setup
    @instance_busy = NewRelic::Agent.agent.stats_engine.get_stats('Instance/Busy')
    @dispatch_stat = NewRelic::Agent.agent.stats_engine.get_stats 'Rails/HTTP Dispatch'
    @mongrel_queue_stat = NewRelic::Agent.agent.stats_engine.get_stats 'WebFrontend/Mongrel/Average Queue Time'

    NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.harvest_busy
    @instance_busy.reset
    @dispatch_stat.reset
    @mongrel_queue_stat.reset

  end
  
  def test_normal_call
    d = FunnyDispatcher.new
    assert !NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.is_busy?
    d.newrelic_dispatcher_start
    sleep 1.0
    assert NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.is_busy?
    d.newrelic_dispatcher_finish
    assert !NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.is_busy?
    assert_nil Thread.current[:newrelic_t0]
    NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.harvest_busy

    assert_equal 1, @instance_busy.call_count
    assert_equal 1, @dispatch_stat.call_count
    assert_equal 0, @mongrel_queue_stat.call_count
    assert @dispatch_stat.total_call_time >= 1.0, "Total call time must be at least one second"
    assert @instance_busy.total_call_time > 0.9 && @instance_busy.total_call_time <= 1.0, "instance busy = #{@instance_busy.inspect}"
  end
  def test_recursive_call
    d = FunnyDispatcher.new
    assert !NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.is_busy?
    d.newrelic_dispatcher_start
    assert NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.is_busy?
    d.newrelic_dispatcher_start
    assert NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.is_busy?
    d.newrelic_dispatcher_finish
    assert !NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.is_busy?
    d.newrelic_dispatcher_finish
    assert !NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.is_busy?
    assert_nil Thread.current[:newrelic_t0]
    NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.harvest_busy
    assert_equal 1, @instance_busy.call_count  
  end
end
