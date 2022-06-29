# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../../../test_helper'

class NewRelic::Agent::Instrumentation::TaskInstrumentationTest < Minitest::Test
  include NewRelic::Agent::Instrumentation::ControllerInstrumentation

  def run_task_inner(n)
    return if n == 0
    run_task_inner(n - 1)
  end

  def run_task_outer(n = 0)
    run_task_inner(n)
    run_task_inner(n)
  end

  def run_task_exception
    NewRelic::Agent.add_custom_attributes(:custom_one => 'one custom val')
    raise "This is an error"
  end

  def run_background_job
    "This is a background job"
  end

  add_transaction_tracer :run_task_exception
  add_transaction_tracer :run_task_inner, :name => 'inner_task_#{args[0]}'
  add_transaction_tracer :run_task_outer, :name => 'outer_task', :params => '{ :level => args[0] }'
  add_transaction_tracer :run_background_job, :category => :task

  def setup
    @agent = NewRelic::Agent.instance
    @agent.transaction_sampler.reset!
    @agent.stats_engine.clear_stats
  end

  #
  # Tests
  #

  def test_should_run
    run_task_inner(0)
    assert_metrics_recorded_exclusive([
      'Supportability/API/perform_action_with_newrelic_trace',
      'Supportability/API/recording_web_transaction?',
      'Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_0',
      'Apdex/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_0',
      'WebTransactionTotalTime',
      'WebTransactionTotalTime/Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_0',
      'HttpDispatcher',
      'ApdexAll',
      'Apdex',
      'DurationByCaller/Unknown/Unknown/Unknown/Unknown/all',
      'DurationByCaller/Unknown/Unknown/Unknown/Unknown/allWeb'
    ])
  end

  def test_should_handle_single_recursive_invocation
    run_task_inner(1)
    assert_metrics_recorded_exclusive(
      [
        'Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_0',

        'Nested/Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_0',
        [
          'Nested/Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_0',
          'Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_0'
        ],

        'Nested/Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_1',
        [
          'Nested/Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_1',
          'Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_0'
        ]
      ],
      :filter => /^(Sub)?Controller/
    )
  end

  def test_should_handle_recursive_task_invocations
    run_task_inner(3)
    assert_metrics_recorded_exclusive(
      [
        'Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_0',

        'Nested/Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_0',
        [
          'Nested/Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_0',
          'Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_0'
        ],

        'Nested/Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_1',
        [
          'Nested/Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_1',
          'Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_0'
        ],

        'Nested/Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_2',
        [
          'Nested/Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_2',
          'Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_0'
        ],

        'Nested/Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_3',
        [
          'Nested/Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_3',
          'Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_0'
        ]
      ],
      :filter => /^(Nested\/)?Controller/
    )
  end

  def test_should_handle_nested_task_invocations
    run_task_outer(3)
    assert_metrics_recorded({
      'Nested/Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/outer_task' => {:call_count => 1},
      'Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_0' => {:call_count => 1}
    })
  end

  def test_transaction
    with_config(:capture_params => true) do
      run_task_outer(10)
    end

    assert_metrics_recorded({
      'Nested/Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/outer_task' => {:call_count => 1},
      'Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/inner_task_0' => {:call_count => 1}
    })
    assert_metrics_not_recorded(['Controller'])

    sample = @agent.transaction_sampler.last_sample

    refute_nil(sample)
    cpu_time = attributes_for(sample, :intrinsic)[:cpu_time]

    refute_nil(cpu_time, "cpu time nil: \n#{sample}")
    assert(cpu_time >= 0, "cpu time: #{cpu_time},\n#{sample}")
    assert_equal(10, attributes_for(sample, :agent)['request.parameters.level'])
  end

  def test_perform_action_with_newrelic_trace_saves_params
    account = 'Redrocks'
    with_config(:capture_params => true) do
      perform_action_with_newrelic_trace(:name => 'hello', :force => true,
        :params => {:account => account}) do
        self.class.inspect
      end
    end

    assert_metrics_recorded(['Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/hello'])
    sample = @agent.transaction_sampler.last_sample
    refute_nil(sample)
    assert_equal(account, attributes_for(sample, :agent)['request.parameters.account'])
  end

  def test_errors_are_noticed_and_not_swallowed
    @agent.error_collector.expects(:notice_error).once
    assert_raises(RuntimeError) { run_task_exception }
  end

  def test_error_collector_captures_custom_params
    @agent.error_collector.error_trace_aggregator.harvest!
    run_task_exception rescue nil
    errors = @agent.error_collector.error_trace_aggregator.harvest!

    assert_equal(1, errors.size)

    error = errors.first
    assert_equal("Controller/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/run_task_exception", error.path)
    refute_nil(error.stack_trace)

    result = error.attributes.custom_attributes_for(NewRelic::Agent::AttributeFilter::DST_TRANSACTION_TRACER)
    refute_nil(result["custom_one"])
  end

  def test_instrument_background_job
    run_background_job
    assert_metrics_recorded([
      'OtherTransaction/Background/NewRelic::Agent::Instrumentation::TaskInstrumentationTest/run_background_job',
      'OtherTransaction/Background/all',
      'OtherTransaction/all'
    ])
  end
end
