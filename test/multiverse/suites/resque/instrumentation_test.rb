# https://newrelic.atlassian.net/browse/RUBY-669

require 'resque'
require 'test/unit'
require 'logger'
require 'newrelic_rpm'
require 'fake_collector'
require File.join(File.dirname(__FILE__), 'resque_setup')

class ResqueTest < Test::Unit::TestCase
  JOB_COUNT = 5
  COLLECTOR_PORT = ENV['NEWRELIC_MULTIVERSE_FAKE_COLLECTOR_PORT']

  def setup
    $collector ||= NewRelic::FakeCollector.new
    $collector.reset
    $collector.run(COLLECTOR_PORT)

    JOB_COUNT.times {|i| Resque.enqueue(JobForTesting, 'index_key', i + 1) }

    start_worker
    wait_for_jobs
    stop_worker
  end

  def start_worker
    worker_cmd = "NEWRELIC_DISPATCHER=resque QUEUE=* bundle exec rake resque:work"
    @worker_pid = Process.fork
    Process.exec(worker_cmd) if @worker_pid.nil?
  end

  def stop_worker
    Process.kill("QUIT", @worker_pid)
    Process.waitpid(@worker_pid)
  end

  def wait_for_jobs
    # JRuby barfs in the timeout on trying to read from Redis.
    time_for_jobs = 5

    t0 = Time.now.to_f
    while Resque.info[:pending] != 0
      sleep(0.1)
      if (Time.now.to_f - t0) > time_for_jobs
        stop_worker
        raise "Timed out waiting #{time_for_jobs}s for completion of #{JOB_COUNT} jobs"
      end
    end
  end

  def teardown
    $redis.set('index_key', 0)
    $redis.del('queue:resque_test')
    $collector.reset
  end

  def test_all_jobs_ran
    assert_equal JOB_COUNT, $redis.get('index_key').to_i
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
