# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class RakeTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  def after_setup
    # Currently necessary since we don't force agent startup/wait on connect
    # in our rake instrumentation yet.
    ENV['NEW_RELIC_SYNC_STARTUP'] = 'true'

    ENV['NEW_RELIC_PORT'] = $collector.port.to_s
  end

  def after_teardown
    unless passed?
      puts @output
    end
  end

  def test_disabling_rake_instrumentation
    ENV["NEW_RELIC_DISABLE_RAKE"] = "true"

    run_rake
    refute_any_rake_metrics
  ensure
    ENV["NEW_RELIC_DISABLE_RAKE"] = nil
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

  def run_rake(commands = "", allow_failure = false)
    full_command = "bundle exec rake #{commands} 2>&1"
    @output = `#{full_command}`

    if !allow_failure
      assert $?.success?, "Failed during '#{full_command}'"
    end
  end

  def with_tasks_traced(*tasks)
    ENV["NEW_RELIC_RAKE_TASKS"] = tasks.join(",")
    yield
  ensure
    ENV["NEW_RELIC_RAKE_TASKS"] = nil
  end

  def assert_metric_names_posted(*expected_names)
    actual_names = single_metrics_post.metric_names
    expected_names.each do |expected_name|
      assert_includes actual_names, expected_name
    end
  end

  def refute_metric_names_posted(*expected_names)
    actual_names = single_metrics_post.metric_names
    expected_names.each do |expected_name|
      refute_includes actual_names, expected_name
    end
  end

  def refute_any_rake_metrics
    $collector.calls_for("metric_data").each do |metric_post|
      metric_post.metric_names.each do |metric_name|
        refute_match /^OtherTransaction.*/, metric_name
        refute_match /^Rake.*/, metric_name
      end
    end
  end
end
