# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

# https://newrelic.atlassian.net/browse/RUBY-775

require File.join(File.dirname(__FILE__), "sidekiq_server")
SidekiqServer.instance.run

# Important to require after Sidekiq server starts for middleware to install
require 'newrelic_rpm'

require 'logger'
require 'stringio'

require 'fake_collector'
require File.join(File.dirname(__FILE__), "test_model")
require File.join(File.dirname(__FILE__), "test_worker")

class SidekiqTest < Minitest::Test
  JOB_COUNT = 5

  ROLLUP_METRIC = 'OtherTransaction/SidekiqJob/all'
  TRANSACTION_NAME = 'OtherTransaction/SidekiqJob/TestWorker/perform'
  DELAYED_TRANSACTION_NAME = 'OtherTransaction/SidekiqJob/TestModel/do_work'
  DELAYED_FAILED_TXN_NAME = 'OtherTransaction/SidekiqJob/Sidekiq::Extensions::DelayedClass/perform'

  include MultiverseHelpers

  setup_and_teardown_agent do
    TestWorker.register_signal('jobs_completed')
    @sidekiq_log = ::StringIO.new

    string_logger = ::Logger.new(@sidekiq_log)
    string_logger.formatter = Sidekiq.logger.formatter
    Sidekiq.logger = string_logger
  end

  def teardown
    teardown_agent
    if !passed? || ENV["VERBOSE"]
      @sidekiq_log.rewind
      puts @sidekiq_log.read
    end
  end

  def run_jobs
    run_and_transmit do |i|
      TestWorker.perform_async('jobs_completed', i + 1)
    end
  end

  def run_delayed
    run_and_transmit do |i|
      TestModel.delay(:queue => SidekiqServer.instance.queue_name, :retry => false).do_work
    end
  end

  def run_and_transmit
    with_config(:'transaction_tracer.transaction_threshold' => 0.0) do
      TestWorker.run_jobs(JOB_COUNT) do |i|
        yield i
      end
    end

    run_harvest
  end

  if defined?(Sidekiq::VERSION) && Sidekiq::VERSION.split('.').first.to_i < 5
    def test_delayed
      run_delayed
      assert_metric_and_call_count(ROLLUP_METRIC, JOB_COUNT)
      assert_metric_and_call_count(DELAYED_TRANSACTION_NAME, JOB_COUNT)
    end

    def test_delayed_with_malformed_yaml
      YAML.stubs(:load).raises(RuntimeError.new("Ouch"))
      run_delayed
      assert_metric_and_call_count(ROLLUP_METRIC, JOB_COUNT)
      if RUBY_VERSION >= '3.0.0'
        assert_metric_and_call_count(DELAYED_TRANSACTION_NAME, JOB_COUNT)
      else
        assert_metric_and_call_count(DELAYED_FAILED_TXN_NAME, JOB_COUNT)
      end
    end
  end

  def test_all_jobs_ran
    run_jobs
    completed_jobs = Set.new(TestWorker.records_for('jobs_completed').map(&:to_i))
    expected_completed_jobs = Set.new((1..JOB_COUNT).to_a)
    assert_equal(expected_completed_jobs, completed_jobs)
  end

  def test_distributed_trace_instrumentation
    @config = {
      :'distributed_tracing.enabled' => true,
      :account_id => "190",
      :primary_application_id => "46954",
      :trusted_account_key => "trust_this!"
    }
    NewRelic::Agent::DistributedTracePayload.stubs(:connected?).returns(true)
    NewRelic::Agent.config.add_config_for_testing(@config)

    in_transaction 'test_txn' do |t|
      run_jobs
    end

    assert_metric_and_call_count "Supportability/TraceContext/Accept/Success", JOB_COUNT # method for metrics created on server side
    assert_metrics_recorded "Supportability/DistributedTrace/CreatePayload/Success" # method for metrics created on the client side

    NewRelic::Agent.config.remove_config(@config)
    NewRelic::Agent.config.reset_to_defaults
    NewRelic::Agent.drop_buffered_data
  end

  def test_agent_posts_correct_metric_data
    run_jobs
    assert_metric_and_call_count(ROLLUP_METRIC, JOB_COUNT)
    assert_metric_and_call_count(TRANSACTION_NAME, JOB_COUNT)
  end

  def test_doesnt_capture_args_by_default
    stub_for_span_collection

    run_jobs
    refute_attributes_on_transaction_trace
    refute_attributes_on_events
  end

  def test_isnt_influenced_by_global_capture_params
    stub_for_span_collection

    with_config(:capture_params => true) do
      run_jobs
    end
    refute_attributes_on_transaction_trace
    refute_attributes_on_events
  end

  def test_agent_posts_captured_args_to_job
    stub_for_span_collection

    with_config(:'sidekiq.capture_params' => true) do
      run_jobs
    end

    assert_attributes_on_transaction_trace
    refute_attributes_on_events
  end

  def test_arguments_are_captured_on_transaction_and_span_events_when_enabled
    stub_for_span_collection

    with_config(:'attributes.include' => 'job.sidekiq.args.*') do
      run_jobs
    end

    assert_attributes_on_events
  end

  def test_captures_errors_from_job
    TestWorker.fail = true
    run_jobs
    assert_error_for_each_job
  ensure
    TestWorker.fail = false
  end

  def test_captures_sidekiq_internal_errors
    # When testing internal Sidekiq error capturing, we're looking to
    # ensure Sidekiq properly forwards errors to our custom error handler
    # in order for us to notice the error.

    exception = StandardError.new('foo')
    NewRelic::Agent.expects(:notice_error).with(exception)
    Sidekiq::CLI.instance.handle_exception(exception)
  end

  def assert_metric_and_call_count(name, expected_call_count)
    metric_data = $collector.calls_for('metric_data')
    assert_equal(1, metric_data.size, "expected exactly one metric_data post from agent")

    metric = metric_data.first.metrics.find { |m| m[0]['name'] == name }
    assert(metric, "Could not find metric named #{name}. Did have metrics:\n" +
                   metric_data.first.metrics.map { |m| m[0]['name'] }.join("\t\n"))

    call_count = metric[1][0]
    assert_equal(expected_call_count, call_count)
  end

  def assert_attributes_on_transaction_trace
    transaction_samples = $collector.calls_for('transaction_sample_data')
    refute transaction_samples.empty?, "Expected a transaction trace"

    transaction_samples.each do |post|
      post.samples.each do |sample|
        assert_equal sample.metric_name, TRANSACTION_NAME, "Huh, that transaction shouldn't be in there!"

        actual = sample.agent_attributes.keys.to_set
        expected = Set.new ["job.sidekiq.args.0", "job.sidekiq.args.1"]
        assert_equal expected, actual
      end
    end
  end

  def refute_attributes_on_transaction_trace
    transaction_samples = $collector.calls_for('transaction_sample_data')
    refute transaction_samples.empty?, "Didn't find any transaction samples!"

    transaction_samples.each do |post|
      post.samples.each do |sample|
        assert_equal sample.metric_name, TRANSACTION_NAME, "Huh, that transaction shouldn't be in there!"
        assert sample.agent_attributes.keys.none? { |k| k =~ /^job.sidekiq.args.*/ }
      end
    end
  end

  def assert_attributes_on_events
    transaction_event_posts = $collector.calls_for('analytic_event_data')[0].events
    span_event_posts = $collector.calls_for('span_event_data')[0].events
    events = transaction_event_posts + span_event_posts
    events.each do |event|
      assert_includes event[2].keys, "job.sidekiq.args.0"
      assert_includes event[2].keys, "job.sidekiq.args.1"
    end
  end

  def refute_attributes_on_events
    transaction_event_posts = $collector.calls_for('analytic_event_data')[0].events
    span_event_posts = $collector.calls_for('span_event_data')[0].events
    events = transaction_event_posts + span_event_posts

    events.each do |event|
      assert event[2].keys.none? { |k| k.start_with?("job.sidekiq.args") }, "Found unexpected sidekiq arguments"
    end
  end

  def assert_error_for_each_job(txn_name = TRANSACTION_NAME)
    error_posts = $collector.calls_for("error_data")
    assert_equal 1, error_posts.length, "Wrong number of error posts!"

    errors = error_posts.first
    assert_equal JOB_COUNT, errors.errors.length, "Wrong number of errors noticed!"

    assert_metric_and_call_count('Errors/all', JOB_COUNT)
    if txn_name
      assert_metric_and_call_count('Errors/allOther', JOB_COUNT)
      assert_metric_and_call_count("Errors/#{TRANSACTION_NAME}", JOB_COUNT)
    end
  end
end
