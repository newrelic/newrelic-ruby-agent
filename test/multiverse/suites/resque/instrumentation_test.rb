# https://newrelic.atlassian.net/browse/RUBY-669

require 'resque'
require 'test/unit'
require 'logger'
require 'newrelic_rpm'
require 'fake_collector'

REDIS_PORT = ENV["NEWRELIC_MULTIVERSE_REDIS_PORT"]

class JobForTesting
  @queue = :resque_test

  def self.perform(key, val, sleep_duration=0)
    sleep sleep_duration
    Redis.new(:port => REDIS_PORT).set(key, val)
  end
end

class ResqueTest < Test::Unit::TestCase
  JOB_COUNT = 5

  def setup
    @redis = Redis.new(:port => REDIS_PORT)
    Resque.redis = @redis

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

    wait_for_jobs
    worker.shutdown

    NewRelic::Agent.shutdown
  end

  def wait_for_jobs
    # JRuby barfs in the timeout on trying to read from Redis.
    time_for_jobs = 2
    if defined?(JRuby)
      sleep time_for_jobs
    else
      # Give a little time to complete, get out early if we're done....
      Timeout::timeout(time_for_jobs) do
        until Resque.info[:pending] == 0; end
      end
    end
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


  METRIC_VALUES_POSITION = 3

  def test_agent_posts_correct_call_count
    test_metric = 'OtherTransaction/ResqueJob/all'
    metric_data = $collector.calls_for('metric_data').first

    metric_names = metric_data[METRIC_VALUES_POSITION].map{|m| m[0]['name']}
    assert(metric_names.include?(test_metric),
           "#{metric_names.inspect} should include '#{test_metric}'")

    call_count = metric_data[METRIC_VALUES_POSITION].find{|m| m[0]['name'] == test_metric}[1][0]
    assert_equal JOB_COUNT, call_count
  end
end
