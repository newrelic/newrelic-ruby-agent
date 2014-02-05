# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# https://newrelic.atlassian.net/browse/RUBY-669

require 'resque'
require 'logger'
require 'newrelic_rpm'
require 'fake_collector'
require 'multiverse_helpers'
require File.join(File.dirname(__FILE__), "..", "..", "..", "agent_helper")

class ResqueTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  class JobForTesting
    @queue = :resque_test
    @count = 0

    def self.reset_counter
      @count = 0
    end

    def self.count
      @count
    end

    def self.perform(name, sleep_duration=0)
      sleep sleep_duration
      @count += 1
    end
  end

  JOB_COUNT = 5
  TRANSACTION_NAME = 'OtherTransaction/ResqueJob/ResqueTest::JobForTesting/perform'

  def run_jobs
    JobForTesting.reset_counter

    # From multiverse, we only run the Resque jobs inline to check that we
    # are properly instrumenting the methods. Testing of the forking/backgrounding
    # will be done in our upcoming end-to-end testing suites
    Resque.inline = true

    with_config(:'transaction_tracer.transaction_threshold' => 0.0) do
      JOB_COUNT.times do |i|
        Resque.enqueue(JobForTesting, "testing")
      end
    end

    NewRelic::Agent.instance.send(:transmit_data)
  end

  def test_all_jobs_ran
    run_jobs
    assert_equal(JOB_COUNT, JobForTesting.count)
  end

  def test_agent_posts_correct_metric_data
    run_jobs
    assert_metric_and_call_count('Instance/Busy', 1)
    assert_metric_and_call_count('OtherTransaction/ResqueJob/all', JOB_COUNT)
  end

  def test_agent_still_running_after_inline_job
    run_jobs
    assert NewRelic::Agent.instance.started?
  end

  def test_doesnt_capture_args_by_default
    run_jobs
    assert_no_params_on_jobs
  end

  def test_isnt_influenced_by_global_capture_params
    with_config(:capture_params => true) do
      run_jobs
    end
    assert_no_params_on_jobs
  end

  def test_agent_posts_captured_args_to_job
    with_config(:'resque.capture_params' => true) do
      run_jobs
    end

    transaction_samples = $collector.calls_for('transaction_sample_data')
    assert_false transaction_samples.empty?

    transaction_samples.each do |post|
      post.samples.each do |sample|
        assert_equal sample.metric_name, TRANSACTION_NAME, "Huh, that transaction shouldn't be in there!"
        assert_equal sample.tree.custom_params["job_arguments"], ["testing"]
      end
    end
  end

  def assert_metric_and_call_count(name, expected_call_count)
    metric_data = $collector.calls_for('metric_data')
    assert_equal(1, metric_data.size, "expected exactly one metric_data post from agent")

    metric = metric_data.first.metrics.find { |m| m[0]['name'] == name }
    assert(metric, "could not find metric named #{name}")

    call_count = metric[1][0]
    assert_equal(expected_call_count, call_count)
  end

  def assert_no_params_on_jobs
    transaction_samples = $collector.calls_for('transaction_sample_data')
    assert_false transaction_samples.empty?

    transaction_samples.each do |post|
      post.samples.each do |sample|
        assert_equal sample.metric_name, TRANSACTION_NAME, "Huh, that transaction shouldn't be in there!"
        assert_nil sample.tree.custom_params["job_arguments"]
      end
    end
  end
end
