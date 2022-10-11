# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../../lib/new_relic/agent/instrumentation/rake/instrumentation'

class RakeInstrumentationTest < Minitest::Test
  class TesterClass
    include NewRelic::Agent::Instrumentation::Rake::Tracer

    def name; 'Snake'; end
    def timeout; 140.85; end
  end

  class ErrorClass < StandardError; end

  def test_invoke_with_newrelic_tracing_happy_path
    skip 'Requires MiniTest v5+' unless MiniTest::Unit::VERSION > '5.0'

    instance = TesterClass.new
    instance_mock = MiniTest::Mock.new
    with_config('rake.connect_timeout': instance.timeout) do
      NewRelic::Agent::Instrumentation::Rake.stub :should_trace?, true, [instance.name] do
        NewRelic::Agent.stub :instance, instance_mock do
          instance_mock.expect :wait_on_connect, nil, [instance.timeout]
          NewRelic::Agent::Instrumentation::Rake.stub :before_invoke_transaction, nil do
            NewRelic::Agent::Tracer.stub :in_transaction, nil do
              NewRelic::Agent::Instrumentation::Rake.stub :record_attributes, nil do
                instance.invoke_with_newrelic_tracing {}
                instance_mock.verify
              end
            end
          end
        end
      end
    end
  end

  def test_invoke_with_newrelic_tracing_when_tracing_is_disabled
    skip 'Requires MiniTest v5+' unless MiniTest::Unit::VERSION > '5.0'

    instance = TesterClass.new
    NewRelic::Agent::Instrumentation::Rake.stub :should_trace?, false, [instance.name] do
      # make absolutely sure the .config call is not being made
      NewRelic::Agent.stub :config, -> { raise 'kaboom' } do
        result = :result
        assert_equal result, instance.invoke_with_newrelic_tracing { result }
      end
    end
  end

  def test_invoke_with_tracing_with_exception
    skip 'Requires MiniTest v5+' unless MiniTest::Unit::VERSION > '5.0'

    instance = TesterClass.new
    NewRelic::Agent::Instrumentation::Rake.stub :should_trace?, true, [instance.name] do
      error = RuntimeError.new('expected')
      # produce the exception we want to have the method rescue
      NewRelic::Agent.stub :config, -> { raise error } do
        logger = MiniTest::Mock.new
        NewRelic::Agent.stub :logger, logger do
          logger.expect :error, nil, [/^Exception/, error]
          instance.invoke_with_newrelic_tracing {}
          logger.verify
        end
      end
    end
  end

  def test_we_should_install_if_newrelic_rake_is_absent
    skip 'Requires MiniTest v5+' unless MiniTest::Unit::VERSION > '5.0'

    NewRelic::LanguageSupport.stub :bundled_gem?, false, 'newrelic-rake' do
      assert NewRelic::Agent::Instrumentation::Rake.should_install?
    end
  end

  def test_we_should_not_install_if_newrelic_rake_is_present
    skip 'Requires MiniTest v5+' unless MiniTest::Unit::VERSION > '5.0'

    NewRelic::LanguageSupport.stub :bundled_gem?, true, 'newrelic-rake' do
      refute NewRelic::Agent::Instrumentation::Rake.should_install?
    end
  end

  def test_we_should_trace_if_the_task_is_allowlisted
    with_config('rake.tasks': [/instrument me/]) do
      assert NewRelic::Agent::Instrumentation::Rake.should_trace?('please instrument me')
    end
  end

  def test_we_should_not_trace_if_the_task_is_not_allowlisted
    with_config('rake.tasks': [/instrument me/]) do
      refute NewRelic::Agent::Instrumentation::Rake.should_trace?('new task I have not yet instrumented')
    end
  end

  def test_a_task_is_monkeypatched_for_execution_instrumentation
    skip 'Requires MiniTest v5+' unless MiniTest::Unit::VERSION > '5.0'

    name = 'Call the Ships to Port'
    task = OpenStruct.new
    task.name = name
    child_task = OpenStruct.new
    child_task.instance_variable_set(:@__newrelic_instrumented_execute, true)
    prerequisite_tasks = [child_task]
    task.prerequisite_tasks = prerequisite_tasks
    scope_it = proc { |metric| assert_equal "Rake/execute/#{name}", metric }
    NewRelic::Agent::MethodTracer.stub :trace_execution_scoped, scope_it, [/^Rake/] do
      assert_equal prerequisite_tasks, NewRelic::Agent::Instrumentation::Rake.instrument_execute(task)
      task.execute
    end
  end

  def test_a_task_is_not_monkeypatched_a_second_time
    task = OpenStruct.new
    task.instance_variable_set(:@__newrelic_instrumented_execute, true)
    # guarantee that #instance_variable_set is not invoked again
    def task.instance_variable_set; raise 'kaboom'; end

    assert_nil NewRelic::Agent::Instrumentation::Rake.instrument_execute(task)
  end

  def test_instrument_execute_covers_super
    task = OpenStruct.new
    task.prerequisite_tasks = []
    NewRelic::Agent::Instrumentation::Rake.instrument_execute(task)
    task.execute
    assert task.instance_variable_get(:@__newrelic_instrumented_execute)
  end

  def test_before_invoke_transaction_with_concurrent_invocation_and_current_transaction
    task = OpenStruct.new(application: OpenStruct.new(options: OpenStruct.new(always_multitask: true)),
      prerequisite_tasks: [OpenStruct.new(name: 'prereq')])
    NewRelic::Agent::Instrumentation::Rake.class_eval do
      def ensure_at_exit; end
    end
    NewRelic::Agent::Instrumentation::Rake.before_invoke_transaction(task)
    txn = MiniTest::Mock.new
    segment = MiniTest::Mock.new
    txn.expect :current_segment, segment
    segment.expect :params, {}
    NewRelic::Agent::Tracer.stub :current_transaction, txn do
      task.execute
      task.invoke_prerequisites_concurrently
      txn.verify
      segment.verify
    end
  end

  def test_before_invoke_transaction_with_concurrent_invocation_without_transaction
    prereq = MiniTest::Mock.new
    prereq.expect :name, 'name'
    task = OpenStruct.new(application: OpenStruct.new(options: OpenStruct.new(always_multitask: true)),
      prerequisite_tasks: [prereq])
    NewRelic::Agent::Instrumentation::Rake.before_invoke_transaction(task)
    NewRelic::Agent::Tracer.stub :current_transaction, nil do
      task.execute
      task.invoke_prerequisites_concurrently
      prereq.verify
    end
  end

  def test_before_invoke_transaction_with_execute
    prereq = MiniTest::Mock.new
    prereq.expect :instance_variable_get, nil, [:@__newrelic_instrumented_execute]
    prereq.expect :instance_variable_set, nil, [:@__newrelic_instrumented_execute, true]
    prereq.expect :instance_eval, nil, []
    prereq.expect :prerequisite_tasks, [], []
    task = OpenStruct.new(application: OpenStruct.new(options: OpenStruct.new(always_multitask: false)),
      prerequisite_tasks: [prereq])
    NewRelic::Agent::Instrumentation::Rake.before_invoke_transaction(task)
    NewRelic::Agent::Tracer.stub :current_transaction, nil do
      task.execute
      task.invoke_prerequisites_concurrently
      prereq.verify
    end
  end

  def test_before_invoke_transaction_with_exception_raised
    logger = MiniTest::Mock.new
    logger.expect :error, nil, [/^Error during/, NoMethodError]
    NewRelic::Agent.stub :logger, logger do
      NewRelic::Agent::Instrumentation::Rake.before_invoke_transaction(nil)
      logger.verify
    end
  end

  def test_record_attributes_with_named_args
    top_level_tasks = %w[James Meowth]
    named_args = %w[Team Rocket]
    task = OpenStruct.new(application: OpenStruct.new(top_level_tasks: top_level_tasks),
      arg_names: %w[Jessie])
    NewRelic::Agent::Instrumentation::Rake.stub :name_the_args, named_args do
      untrusted = proc { |input|
        assert_includes [{command: top_level_tasks.join(' ')}, named_args], input
      }
      NewRelic::Agent::Transaction.stub :merge_untrusted_agent_attributes, untrusted do
        NewRelic::Agent::Instrumentation::Rake.record_attributes(nil, task)
      end
    end
  end

  def test_record_attributes_without_named_args
    skip 'Requires MiniTest v5+' unless MiniTest::Unit::VERSION > '5.0'

    top_level_tasks = %w[James Meowth]
    named_args = []
    task = OpenStruct.new(application: OpenStruct.new(top_level_tasks: top_level_tasks),
      arg_names: %w[Jessie])
    NewRelic::Agent::Instrumentation::Rake.stub :name_the_args, named_args do
      untrusted = proc { |input|
        assert_includes [{command: top_level_tasks.join(' ')}], input
      }
      NewRelic::Agent::Transaction.stub :merge_untrusted_agent_attributes,
        nil,
        [{command: top_level_tasks.join(' ')}] do
        NewRelic::Agent::Instrumentation::Rake.record_attributes(nil, task)
      end
    end
  end

  def test_record_attributes_with_exception
    logger = MiniTest::Mock.new
    logger.expect :error, nil, [/^Error during/, ErrorClass]
    top_level_tasks = %w[James Meowth]
    named_args = []
    task = OpenStruct.new(application: OpenStruct.new(top_level_tasks: top_level_tasks),
      arg_names: %w[Jessie])
    untrusted = proc { |_args| raise ErrorClass.new('kaboom') }
    NewRelic::Agent::Transaction.stub :merge_untrusted_agent_attributes, untrusted do
      NewRelic::Agent.stub :logger, logger do
        NewRelic::Agent::Instrumentation::Rake.record_attributes(nil, task)
        logger.verify
      end
    end
  end

  def test_name_the_args_with_unfulfilled
    args = %w[arg1 arg2]
    names = %w[name1 name2 name3]
    expected = {'name1' => 'arg1', 'name2' => 'arg2', 'name3' => nil}
    result = NewRelic::Agent::Instrumentation::Rake.name_the_args(args, names)
    assert_equal expected, result
  end

  def test_name_the_args_without_unfulfilled
    args = %w[arg1 arg2]
    names = %w[name1 name2]
    expected = {'name1' => 'arg1', 'name2' => 'arg2'}
    result = NewRelic::Agent::Instrumentation::Rake.name_the_args(args, names)
    assert_equal expected, result
  end
end
