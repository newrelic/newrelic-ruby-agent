# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module RakeTestHelper
  def run_rake(commands = "", allow_failure = false)
    full_command = "bundle exec rake #{commands} 2>&1"
    @output = `#{full_command}`

    if !allow_failure
      assert $?.success?, "Failed during '#{full_command}'"
    end
  end

  def with_tasks_traced(*tasks)
    with_environment("NEW_RELIC_RAKE_TASKS" => tasks.join(",")) do
      yield
    end
  end

  def without_attributes(*tasks)
    with_environment("NEW_RELIC_ATTRIBUTES_EXCLUDE" => "*") do
      yield
    end
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
