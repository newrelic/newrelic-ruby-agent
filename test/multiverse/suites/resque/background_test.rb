# https://newrelic.atlassian.net/browse/RUBY-857

require 'resque'
require 'test/unit'
require 'logger'
require 'newrelic_rpm'
require 'fake_collector'
require File.join(File.dirname(__FILE__), 'resque_setup')

class BackgroundResqueTest < Test::Unit::TestCase
  JOB_COUNT      = 5
  PIDFILE        = "backgroundtest.pid"
  COLLECTOR_PORT = ENV['NEWRELIC_MULTIVERSE_FAKE_COLLECTOR_PORT']

  def setup
    $collector ||= NewRelic::FakeCollector.new
    $collector.reset
    $collector.run(COLLECTOR_PORT)

    JOB_COUNT.times {|i| Resque.enqueue(JobForTesting, 'index_key', i + 1) }

    begin
      start_worker
      wait_for_jobs
    ensure
      stop_worker
    end
  end

  def start_worker
    worker_cmd = "PIDFILE=#{PIDFILE} TERM_CHILD=1 RESQUE_TERM_TIMEOUT=1 BACKGROUND=1 " +
      "NEWRELIC_DISPATCHER=resque QUEUE=* bundle exec rake resque:work"
    system(worker_cmd)
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    return true
  rescue Errno::ESRCH
    return false
  end


  def stop_worker
    daemon_pid = File.read( PIDFILE ) or raise "No pidfile (#{PIDFILE}) found!"
    daemon_pid = daemon_pid.to_i

    tries = 0
    while process_alive?(daemon_pid) && tries < 3
      Process.kill('TERM', daemon_pid)
      sleep 4 # default resque TERM timeout
      tries += 1
    end

    if process_alive?(daemon_pid)
      $stderr.puts "Oops. Daemon (pid #daemon_pid) is still running. Trying to halt it with SIGQUIT"
      Process.kill('QUIT', daemon_pid)
      sleep 1

      # If it's still alive, someone will likely have to go kill the process manually. 
      # Alternatively, we could kill -9 it, but I decided to err on the side of caution
      if process_alive?(daemon_pid)
        raise "Resque is zombified. You might have to clean up process #{daemon_pid} manually."
      end
    end

  end

  def wait_for_jobs
    time_for_jobs = 5.0

    begin
      Timeout.timeout(time_for_jobs) { sleep(0.1) until Resque.info[:pending].zero? }
    rescue Timeout::Error => err
      raise err.exception("waiting #{time_for_jobs}s for completion of #{JOB_COUNT} jobs")
    end
  end

  def teardown
    $redis.set('index_key', 0)
    $redis.del('queue:resque_test')
    $collector.reset
    File.unlink(PIDFILE) if File.file?(PIDFILE)
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
