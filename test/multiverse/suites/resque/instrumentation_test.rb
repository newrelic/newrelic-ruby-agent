# https://newrelic.atlassian.net/browse/RUBY-669

require 'resque'
require 'test/unit'
require 'logger'
require 'newrelic_rpm'
require 'new_relic/fake_collector'

class JobForTesting
  @queue = :resque_test

  def self.perform(key, val, sleep_duration=0)
    sleep sleep_duration
    Redis.new.set(key, val)
  end
end

class ResqueTest < Test::Unit::TestCase
  JOB_COUNT = 5

  def setup
    @redis = Redis.new

    $collector ||= NewRelic::FakeCollector.new
    $collector.reset
    $collector.run

    NewRelic::Agent.manual_start
    DependencyDetection.detect!

    JOB_COUNT.times {|i| Resque.enqueue(JobForTesting, 'index_key', i + 1) }
    worker = Resque::Worker.new(:resque_test)
    Thread.new do
      worker.work
    end.abort_on_exception = true
    sleep 1 # give the worker some time to process
    worker.shutdown

    NewRelic::Agent.shutdown
    sleep 0.5 # give the agent some time to report after shutdown
  end

  def teardown
    @redis.set('index_key', 0)
    Resque.redis.del('queue:resque_test')
    $collector.reset
  end

  def test_resque_instrumentation_is_installed
    assert DependencyDetection.installed?(:resque)
  end

  def test_all_jobs_ran
    assert_equal JOB_COUNT, @redis.get('index_key').to_i
  end

  def test_agent_makes_only_one_metric_post
    assert_equal(1, $collector.agent_data.select{|x| x.action == 'metric_data'}.size,
                 "wrong number of metric_data posts in #{$collector.agent_data.inspect}")
  end

  def test_agent_posts_correct_call_count
    test_metric = 'OtherTransaction/ResqueJob/all'
    metric_data = $collector.agent_data.find{|x| x.action == 'metric_data'}

    metric_names = metric_data.body[3].map(&:metric_spec).map(&:name)
    assert(metric_names.include?(test_metric),
           "#{metric_names.inspect} should include '#{test_metric}'")

    call_count = metric_data.body[3].find{|m| m.metric_spec.name == test_metric}.stats.call_count
    assert_equal JOB_COUNT, call_count
  end
end
