# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# https://newrelic.atlassian.net/browse/RUBY-775

require 'sidekiq'
require 'test/unit'
require 'newrelic_rpm'
require 'fake_collector'

class ResqueTest < Test::Unit::TestCase
  JOB_COUNT = 5
  COLLECTOR_PORT = ENV['NEWRELIC_MULTIVERSE_FAKE_COLLECTOR_PORT']

  def setup
    $collector ||= NewRelic::FakeCollector.new
    $collector.reset
    $collector.run(COLLECTOR_PORT)
    @pidfile = "sidekiq.#{$$}.pid"
    @sidekiq_log = "log/sidekiq.#{$$}.log"
    JOB_COUNT.times do |i|
      TestWorker.perform_async('jobs_completed', i + 1)
    end
  end

  def teardown
    $redis.flushall
    File.unlink(@pidfile) if File.exist?(@pidfile)
    File.unlink(@sidekiq_log) if File.exist?(@sidekiq_log)
  end

  def start_worker(opts={})
    daemon_arg = opts[:daemonize] ? '-d' : ''
    worker_cmd = "bundle exec sidekiq #{daemon_arg} -P #{@pidfile} -L #{@sidekiq_log} -r ./app.rb &"
    system(worker_cmd)
  end

  def stop_worker
    worker_pid = File.read(@pidfile).to_i
    Process.kill("TERM", worker_pid)
    begin
      Timeout.timeout(5) { sleep(1) until !process_alive?(worker_pid) }
    rescue Timeout::Error => e
      raise e.exception("timed out waiting for sidekiq worker exit")
    end
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    return true
  rescue Errno::ESRCH
    return false
  end

  def wait_for_jobs
    time_for_jobs = 5
    begin
      stats = Sidekiq::Stats.new
      Timeout.timeout(time_for_jobs) { sleep(0.1) until stats.processed == JOB_COUNT }
    rescue Timeout::Error => err
      raise err.exception("waiting #{time_for_jobs}s for completion of #{JOB_COUNT} jobs")
    end
  end

  def run_worker(opts={})
    begin
      start_worker(opts)
      wait_for_jobs
    ensure
      stop_worker
    end
  end

  # The point here is to supress Sidekiq log output for passing tests, but
  # dump the log for failing tests.
  def capture_sidekiq_log
    File.unlink(@sidekiq_log) if File.exist?(@sidekiq_log)
    @sidekiq_log = "log/sidekiq.#{$$}.log"
    begin
      yield
    rescue Exception => e
      if File.exist?(@sidekiq_log)
        log_contents = File.read(@sidekiq_log)
        $stderr.puts "Sidekiq log contents (#{@sidekiq_log}):"
        $stderr.puts log_contents
      end
      raise e
    end
    File.unlink(@sidekiq_log) if File.exist?(@sidekiq_log)
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

  def test_all_jobs_ran
    capture_sidekiq_log do
      run_worker
      completed_jobs = Set.new($redis.smembers('jobs_completed').map(&:to_i))
      expected_completed_jobs = Set.new((1..JOB_COUNT).to_a)
      assert_equal(expected_completed_jobs, completed_jobs)
    end
  end

  def test_agent_posts_correct_metric_data
    capture_sidekiq_log do
      run_worker
      assert_metric_and_call_count('OtherTransaction/SidekiqJob/all', JOB_COUNT)
    end
  end

  def test_all_jobs_ran_background
    capture_sidekiq_log do
      run_worker(:daemonize => true)
      completed_jobs = Set.new($redis.smembers('jobs_completed').map(&:to_i))
      expected_completed_jobs = Set.new((1..JOB_COUNT).to_a)
      assert_equal(expected_completed_jobs, completed_jobs)
    end
  end

  def test_agent_posts_correct_metric_data_background
    capture_sidekiq_log do
      run_worker(:daemonize => true)
      assert_metric_and_call_count('OtherTransaction/SidekiqJob/all', JOB_COUNT)
    end
  end
end
