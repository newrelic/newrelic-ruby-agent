# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'mocha/api'

class ThreadProfiling < Performance::TestCase
  include Mocha::API
  ITERATIONS_BACKTRACES = 2_000
  ITERATIONS_SUBSCRIBED = 100_000
  ITERATIONS_TRACES = 15

  def recurse(n, final)
    if n == 0
      final.call
    else
      recurse(n - 1, final)
    end
  end

  def block
    @mutex.synchronize do
      @cvar.wait(@mutex)
    end
  end

  def setup
    mocha_setup
    require 'new_relic/agent/threading/backtrace_service'

    @nthreads = 16

    @mutex = Mutex.new
    @cvar = ConditionVariable.new
    @threadq = Queue.new
    @threads = []

    @nthreads.times do
      @threads << Thread.new do
        @threadq << self
        NewRelic::Agent::Transaction.any_instance.stubs(:recording_web_transaction?).returns(true)
        recurse(50, method(:block))
      end
    end

    # Ensure that all threads have had a chance to start up
    started_count = 0
    while started_count < @nthreads
      @threadq.pop
      started_count += 1
    end

    @service = NewRelic::Agent::Threading::BacktraceService.new
    @worker_loop = @service.worker_loop
    def @worker_loop.run; end # we want to drive it manually
  end

  def teardown
    mocha_teardown

    @cvar.broadcast
    @threads.each(&:join)
    mocha_teardown
  rescue Exception => e
    if e.message.include?('Deadlock')
      Thread.list.select(&:alive?).each do |t|
        STDERR.puts '*' * 80
        STDERR.puts "Live thread: #{t.inspect}"
        STDERR.puts 'Backtrace:'
        STDERR.puts (t.backtrace || []).join("\n")
        STDERR.puts '*' * 80
      end
    end

    raise e
  end

  def test_gather_backtraces
    @service.subscribe(NewRelic::Agent::Threading::BacktraceService::ALL_TRANSACTIONS)
    measure(ITERATIONS_BACKTRACES) do
      @service.poll
    end
    @service.unsubscribe(NewRelic::Agent::Threading::BacktraceService::ALL_TRANSACTIONS)
  end

  def test_gather_backtraces_subscribed
    @service.subscribe('eagle')
    measure(ITERATIONS_SUBSCRIBED) do
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @service.poll
      payload = {
        :name => 'eagle',
        :bucket => :request,
        :start_timestamp => t0,
        :duration => Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0,
        :thread => @threads.sample
      }
      @service.on_transaction_finished(payload)
    end
    @service.unsubscribe('eagle')
  end

  def test_generating_traces
    require 'new_relic/agent/threading/thread_profile'

    measure(ITERATIONS_TRACES) do
      profile = ::NewRelic::Agent::Threading::ThreadProfile.new({})

      aggregate_lots_of_nodes(profile, 5, [])

      profile.generate_traces
    end
  end

  def aggregate_lots_of_nodes(profile, depth, trace)
    if depth > 0
      7.times do |i|
        trace.push("path#{i}:#{i + 50}:in `depth#{depth}'")
        aggregate_lots_of_nodes(profile, depth - 1, trace)
        trace.pop
      end
    else
      profile.aggregate(trace, :request, Thread.current)
    end
  end
end
