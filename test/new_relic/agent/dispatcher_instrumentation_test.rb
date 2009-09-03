require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper')) 

class NewRelic::Agent::DispatcherInstrumentationTest < Test::Unit::TestCase
  
  class FunnyDispatcher
    include NewRelic::Agent::Instrumentation::DispatcherInstrumentation
    def newrelic_response_code; end
  end
  def setup
    super
    NewRelic::Agent.manual_start
    NewRelic::Agent.instance.stats_engine.clear_stats
    @instance_busy = NewRelic::Agent.agent.stats_engine.get_stats('Instance/Busy')
    @dispatch_stat = NewRelic::Agent.agent.stats_engine.get_stats 'HttpDispatcher'
    @mongrel_queue_stat = NewRelic::Agent.agent.stats_engine.get_stats 'WebFrontend/Mongrel/Average Queue Time'
  end
  
  def test_normal_call
    d = FunnyDispatcher.new
    assert_equal 0, NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.busy_count
    d.newrelic_dispatcher_start
    sleep 1.0
    assert_equal 1, NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.busy_count
    d.newrelic_dispatcher_finish
    assert_equal 0, NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.busy_count
    assert_nil Thread.current[:newrelic_t0]
    NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.harvest_busy

    assert_equal 1, @instance_busy.call_count
    assert_equal 1, @dispatch_stat.call_count
    assert_equal 0, @mongrel_queue_stat.call_count
    assert @dispatch_stat.total_call_time >= 1.0, "Total call time must be at least one second"
    assert @instance_busy.total_call_time > 0.9 && @instance_busy.total_call_time <= 1.0, "instance busy = #{@instance_busy.inspect}"
  end
  def test_histogram
    d = FunnyDispatcher.new
    d.newrelic_dispatcher_start
    d.newrelic_dispatcher_finish
    bucket = NewRelic::Agent.instance.stats_engine.metrics.find { | m | m =~ /^Response Times/ }
    assert_not_nil bucket
    bucket_stats = NewRelic::Agent.instance.stats_engine.get_stats(bucket)
    assert_equal 1, bucket_stats.call_count
  end
  def test_ignore_zero_counts
    assert_equal 0, @instance_busy.call_count, "Problem with test--instance busy not starting off at zero."
    NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.harvest_busy
    NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.harvest_busy
    NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.harvest_busy
    assert_equal 0, @instance_busy.call_count  
  end
  def test_recursive_call
    d0 = FunnyDispatcher.new
    d1 = FunnyDispatcher.new

    assert_equal 0, @instance_busy.call_count, "Problem with test--instance busy not starting off at zero."

    NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.harvest_busy
    NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.harvest_busy
    assert_equal 0, @instance_busy.call_count  

    assert_equal 0, NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.busy_count
    d0.newrelic_dispatcher_start
    assert_equal 1, NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.busy_count
    d1.newrelic_dispatcher_start
    assert_equal 2, NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.busy_count
    sleep 1
    d0.newrelic_dispatcher_finish
    assert_equal 1, NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.busy_count
    d1.newrelic_dispatcher_finish
    assert_equal 0, NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.busy_count
    assert_nil Thread.current[:newrelic_t0]
    NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.harvest_busy
    assert_equal 1, @instance_busy.call_count  
    assert @instance_busy.total_call_time.between?(1.8, 2.1), "Should be about 200%: #{@instance_busy.total_call_time}"
  end
end
