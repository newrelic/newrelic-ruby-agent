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

class SidekiqTest < MiniTest::Unit::TestCase
  JOB_COUNT = 5

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
    TestWorker.reset
    JOB_COUNT.times do |i|
      TestWorker.perform_async('jobs_completed', i + 1)
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

  METRIC_VALUES_POSITION = 3

  def assert_metric_and_call_count(name, expected_call_count)
    metric_data = $collector.calls_for('metric_data')
    assert_equal(1, metric_data.size, "expected exactly one metric_data post from agent")

    metric = metric_data.first[METRIC_VALUES_POSITION].find { |m| m[0]['name'] == name }
    assert(metric, "could not find metric named #{name}")

    call_count = metric[1][0]
    assert_equal(expected_call_count, call_count)
  end
end
