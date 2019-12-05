# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# Because some envs have Rails, we might not have loaded in the absence of
# initializers running, so kick-start agent to get instrumentation loaded.
NewRelic::Agent.manual_start(:sync_startup => false)

module RakeTestHelper
  def after_setup
    ENV['NEWRELIC_DISABLE_HARVEST_THREAD'] = 'false'
    ENV['NEW_RELIC_PORT'] = $collector.port.to_s
  end

  def after_teardown
    unless passed?
      puts @output
    end
  end

  def run_rake(commands = "", allow_failure = false)
    full_command = "bundle exec rake #{commands} 2>&1"
    puts '*' * 80
    puts "RUN RAKE: #{full_command.inspect}"
    @output = `#{full_command}`
    puts @output
    puts '*' * 80

    if !allow_failure
      assert $?.success?, "Failed during '#{full_command}'"
    end
  end

  def with_tasks_traced(*tasks)
    with_environment(
      "NEW_RELIC_RAKE_TASKS" => tasks.join(","),
      "NEW_RELIC_SYNC_STARTUP" => "true"
    ) do
      yield
    end
  end

  def without_attributes(*tasks)
    with_environment("NEW_RELIC_ATTRIBUTES_EXCLUDE" => "*") do
      yield
    end
  end

  def assert_metric_names_posted(*expected_names)
    expected_names.each do |expected_name|
      assert_includes all_metric_names_posted, expected_name
    end
  end

  def refute_metric_names_posted(*expected_names)
    expected_names.each do |expected_name|
      refute_includes all_metric_names_posted, expected_name
    end
  end

  def refute_any_rake_metrics
    all_metric_names_posted.each do |metric_name|
      refute_match /^OtherTransaction.*/, metric_name
      refute_match /^Rake.*/, metric_name
    end
  end

  def all_metric_names_posted
    $collector.calls_for("metric_data").map do |metric_post|
      metric_post.metric_names
    end.flatten
  end
end
