# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

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
    $redis.del('queue:resque_test')
    $redis.set('index_key', 0)
    Resque::Stat.clear('processed')
    @pidfile = "resque_test.#{$$}.pid"
    JOB_COUNT.times do |i|
      Resque.enqueue(JobForTesting, 'index_key', i + 1)
    end
  end

  def teardown
    File.unlink(@pidfile) if File.file?(@pidfile)
  end

  def start_worker(opts={})
    if opts[:background]
      start_worker_background(opts[:env_vars])
    else
      start_worker_child(opts[:env_vars])
    end
  end

  def stop_worker(opts={})
    opts[:background] ? stop_worker_background : stop_worker_child
  end

  def start_worker_child(env_vars=nil)
    worker_cmd = "#{env_vars} QUEUE=* TERM_CHILD=1 bundle exec rake resque:work"
    @worker_pid = Process.fork
    Process.exec(worker_cmd) if @worker_pid.nil?
  end

  def stop_worker_child
    Process.kill("QUIT", @worker_pid)
    Process.waitpid(@worker_pid)
  end

  def start_worker_background(env_vars=nil)
    worker_cmd = "PIDFILE=#{@pidfile} TERM_CHILD=1 RESQUE_TERM_TIMEOUT=1 BACKGROUND=1 " +
      "#{env_vars} QUEUE=* bundle exec rake resque:work"
    system(worker_cmd)
  end

  def stop_worker_background
    daemon_pid = File.read(@pidfile).to_i

    tries = 0
    while process_alive?(daemon_pid) && tries < 3
      Process.kill('TERM', daemon_pid)
      sleep 4 # default resque TERM timeout
      tries += 1
    end

    if process_alive?(daemon_pid)
      $stderr.puts "Oops. Daemon (pid #{daemon_pid}) is still running. Trying to halt it with SIGQUIT"
      Process.kill('QUIT', daemon_pid)
      sleep 1

      # If it's still alive, someone will likely have to go kill the process manually. 
      # Alternatively, we could kill -9 it, but I decided to err on the side of caution
      if process_alive?(daemon_pid)
        raise "Resque is zombified. You might have to clean up process #{daemon_pid} manually."
      end
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
      Timeout.timeout(time_for_jobs) do
        loop do
          break if Resque.info[:processed] == JOB_COUNT
          sleep(0.1) 
        end
      end
    rescue Timeout::Error => err
      raise err.exception("waiting #{time_for_jobs}s for completion of #{JOB_COUNT} jobs")
    end
  end

  def run_worker(opts={})
    begin
      start_worker(opts)
      wait_for_jobs
    ensure
      stop_worker(opts)
    end
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
    run_worker
    assert_equal(JOB_COUNT, $redis.get('index_key').to_i)
  end

  def test_agent_posts_correct_metric_data
    run_worker
    assert_metric_and_call_count('OtherTransaction/ResqueJob/all', JOB_COUNT)
  end

  if RUBY_VERSION >= '1.9'
    def test_all_jobs_ran_background
      run_worker(:background => true)
      assert_equal(JOB_COUNT, $redis.get('index_key').to_i)
    end

    def test_agent_posts_correct_metric_data_background
      run_worker(:background => true)
      assert_metric_and_call_count('OtherTransaction/ResqueJob/all', JOB_COUNT)
    end
  end
end
