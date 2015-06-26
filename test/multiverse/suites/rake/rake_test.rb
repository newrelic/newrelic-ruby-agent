# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(__FILE__, '..', 'rake_test_helper'))

if ::NewRelic::Agent::Instrumentation::RakeInstrumentation.should_install? &&
class RakeTest < Minitest::Test
  include MultiverseHelpers
  include RakeTestHelper

  setup_and_teardown_agent

  def test_disabling_rake_instrumentation
    with_environment("NEW_RELIC_DISABLE_RAKE" => "true") do
      run_rake
    end

    refute_any_rake_metrics
  end

  def test_doesnt_trace_by_default
    run_rake("untraced")
    refute_any_rake_metrics
  end

  def test_doesnt_trace_with_an_empty_list
    with_tasks_traced("") do
      run_rake
      refute_any_rake_metrics
    end
  end

  def test_timeout_on_connect
    $collector.stub_wait('connect', 5)

    with_environment("NEW_RELIC_RAKE_CONNECT_TIMEOUT" => "0",
                     "NEW_RELIC_LOG" => "stdout") do
      run_rake
    end

    refute_any_rake_metrics
    assert_includes @output, "ERROR : NewRelic::Agent::Agent::InstanceMethods::Connect::WaitOnConnectTimeout: Agent was unable to connect"
  end

  def test_records_transaction_metrics
    run_rake

    assert_metric_names_posted "OtherTransaction/Rake/invoke/default",
                               "OtherTransaction/Rake/all",
                               "OtherTransaction/all",
                               "Rake/execute/before",
                               "Rake/execute/during",
                               "Rake/execute/after"
  end

  def test_records_transaction_trace
    run_rake

    trace = single_transaction_trace_posted
    assert_equal "OtherTransaction/Rake/invoke/default", trace.metric_name

    expected = ["ROOT",
                 ["OtherTransaction/Rake/invoke/default",
                   ["Rake/execute/before"],
                   ["Rake/execute/during"],
                   ["Rake/execute/after"]]]

    assert_equal expected, trace.tree.nodes
  end

  def test_records_transaction_events
    run_rake

    event = single_event_posted[0]
    assert_equal "OtherTransaction/Rake/invoke/default", event["name"]
  end

  def test_records_namespaced_tasks
    with_tasks_traced("named:all") do
      run_rake("named:all")

      assert_metric_names_posted "OtherTransaction/Rake/invoke/named:all",
                                 "OtherTransaction/Rake/all",
                                 "OtherTransaction/all",
                                 "Rake/execute/named:before",
                                 "Rake/execute/named:during",
                                 "Rake/execute/named:after"
    end
  end

  def test_matches_tasks_by_regex
    with_tasks_traced(".*before") do
      run_rake("before named:before during")

      assert_metric_names_posted "OtherTransaction/Rake/invoke/before",
                                 "OtherTransaction/Rake/invoke/named:before"

      refute_metric_names_posted "OtherTransaction/Rake/invoke/during"
    end
  end

  def test_records_tree_of_prereqs
    with_tasks_traced("tree") do
      run_rake("tree")

      assert_metric_names_posted "OtherTransaction/Rake/invoke/tree",
                                 "OtherTransaction/Rake/all",
                                 "OtherTransaction/all",
                                 "Rake/execute/branch1",
                                 "Rake/execute/branch1a",
                                 "Rake/execute/branch1b",
                                 "Rake/execute/branch2",
                                 "Rake/execute/branch2a",
                                 "Rake/execute/branch2b"
    end
  end

  def test_traced_task_as_prereq_doesnt_get_transaction
    with_tasks_traced("default", "before") do
      run_rake

      assert_metric_names_posted "OtherTransaction/Rake/invoke/default",
                                 "OtherTransaction/Rake/all",
                                 "OtherTransaction/all",
                                 "Rake/execute/before",
                                 "Rake/execute/during",
                                 "Rake/execute/after"

      refute_metric_names_posted "OtherTransaction/Rake/invoke/before"
    end
  end

  def test_error_during_task
    with_tasks_traced("boom") do
      run_rake("boom", true)

      expected = "OtherTransaction/Rake/invoke/boom"
      assert_equal expected, single_error_posted.path
    end
  end

  def test_captures_task_arguments
    with_tasks_traced("argument") do
      run_rake("argument[someone,somewhere,vigorously]")

      attributes = single_transaction_trace_posted.agent_attributes
      assert_equal "someone",    attributes["job.rake.args.who"]
      assert_equal "somewhere",  attributes["job.rake.args.where"]
      assert_equal "vigorously", attributes["job.rake.args.2"]
    end
  end

  def test_captures_task_arguments_with_too_few
    with_tasks_traced("argument") do
      run_rake("argument[someone]")

      attributes = single_transaction_trace_posted.agent_attributes
      assert_equal "someone", attributes["job.rake.args.who"]

      refute_includes attributes, "job.rake.args.where"
      refute_includes attributes, "job.rake.args.2"
    end
  end

  def test_doesnt_capture_task_arguments_if_disabled_by_agent_attributes
    with_tasks_traced("argument") do
      without_attributes do
        run_rake("argument[someone,somewhere,vigorously]")

        attributes = single_transaction_trace_posted.agent_attributes
        refute_includes attributes, "job.rake.args.who"
        refute_includes attributes, "job.rake.args.where"
        refute_includes attributes, "job.rake.args.2"
      end
    end
  end

  def test_doesnt_capture_completely_empty_args
    with_tasks_traced("default") do
      run_rake("default")

      attributes = single_transaction_trace_posted.agent_attributes
      refute attributes.keys.any? { |key| key.start_with?("job.rake.args") }
    end
  end

  def test_captures_command_line
    with_tasks_traced("default", "argument") do
      run_rake("argument[someone] default")

      attributes = single_transaction_trace_posted.agent_attributes
      assert_includes attributes["job.rake.command"], "argument[someone]"
      assert_includes attributes["job.rake.command"], "default"
    end
  end

  def test_doesnt_capture_command_line_if_disabled_by_agent_attributes
    with_tasks_traced("default", "argument") do
      without_attributes do
        run_rake("argument[someone] default")

        attributes = single_transaction_trace_posted.agent_attributes
        refute_includes attributes, "job.rake.command"
      end
    end
  end
end
end
