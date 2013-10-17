# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# https://newrelic.atlassian.net/browse/RUBY-775

require 'sidekiq'
require 'sidekiq/testing/inline'
require 'test/unit'
require 'newrelic_rpm'
require 'fake_collector'
require 'multiverse_helpers'
require File.join(File.dirname(__FILE__), "..", "..", "..", "agent_helper")

class SidekiqTest < MiniTest::Unit::TestCase
  JOB_COUNT = 5
  TRANSACTION_NAME = 'OtherTransaction/SidekiqJob/SidekiqTest::TestWorker/perform'

  include MultiverseHelpers

  setup_and_teardown_agent

  class TestWorker
    include Sidekiq::Worker

    @jobs = {}

    def self.reset
      @jobs = {}
    end

    def self.record(key, val)
      @jobs[key] ||= []
      @jobs[key] << val
    end

    def self.records_for(key)
      @jobs[key]
    end

    def perform(key, val)
      TestWorker.record(key, val)
    end
  end

  # Running inline doesn't set up server middlewares
  # Using the client middleware to get there instead
  Sidekiq.configure_client do |config|
    config.client_middleware do |chain|
      chain.add NewRelic::SidekiqInstrumentation
    end
  end

  def run_jobs
    with_config(:'transaction_tracer.transaction_threshold' => 0.0) do
      TestWorker.reset
      JOB_COUNT.times do |i|
        TestWorker.perform_async('jobs_completed', i + 1)
      end
    end

    NewRelic::Agent.instance.send(:transmit_data)
  end

  def test_all_jobs_ran
    run_jobs
    completed_jobs = Set.new(TestWorker.records_for('jobs_completed').map(&:to_i))
    expected_completed_jobs = Set.new((1..JOB_COUNT).to_a)
    assert_equal(expected_completed_jobs, completed_jobs)
  end

  def test_agent_posts_correct_metric_data
    run_jobs
    assert_metric_and_call_count('OtherTransaction/SidekiqJob/all', JOB_COUNT)
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
    with_config(:'sidekiq.capture_params' => true) do
      run_jobs
    end

    transaction_samples = $collector.calls_for('transaction_sample_data')
    assert_false transaction_samples.empty?

    transaction_samples.each do |post|
      post.samples.each do |sample|
        assert_equal sample.metric_name, TRANSACTION_NAME, "Huh, that transaction shouldn't be in there!"

        args = sample.tree.custom_params["job_arguments"]
        assert_equal args.length, 2
        assert_equal args[0], "jobs_completed"
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
