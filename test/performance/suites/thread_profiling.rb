# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class ThreadProfiling < Performance::TestCase
  def recurse(n, final)
    if n == 0
      final.call
    else
      recurse(n-1, final)
    end
  end

  def block
    @mutex.synchronize do
      @cvar.wait(@mutex)
    end
  end

  def setup
    require 'new_relic/agent/threading/backtrace_service'

    @nthreads = 16

    @mutex = Mutex.new
    @cvar = ConditionVariable.new
    @threadq = Queue.new
    @threads = []

    @nthreads.times do
      @threads << Thread.new do
        @threadq << self
        transaction_state = NewRelic::Agent::TransactionState.tl_get
        def transaction_state.in_web_transaction?; true; end
        recurse(50, method(:block))
      end
    end

    # Ensure that all threads have had a chance to start up
    started_count = 0
    while started_count < @nthreads do
      @threadq.pop
      started_count += 1
    end

    @service = NewRelic::Agent::Threading::BacktraceService.new
    @worker_loop = @service.worker_loop
    def @worker_loop.run; end # we want to drive it manually
  end

  def teardown
    @cvar.broadcast
    @threads.each(&:join)
  rescue Exception => e
    if e.message =~ /Deadlock/
      Thread.list.select(&:alive?).each do |t|
        STDERR.puts "*" * 80
        STDERR.puts "Live thread: #{t.inspect}"
        STDERR.puts "Backtrace:"
        STDERR.puts (t.backtrace || []).join("\n")
        STDERR.puts "*" * 80
      end
    end

    raise e
  end

  def test_gather_backtraces
    @service.subscribe(NewRelic::Agent::Threading::BacktraceService::ALL_TRANSACTIONS)
    measure do
      @service.poll
    end
    @service.unsubscribe(NewRelic::Agent::Threading::BacktraceService::ALL_TRANSACTIONS)
  end

  def test_gather_backtraces_subscribed
    @service.subscribe('eagle')
    measure do
      t0 = Time.now.to_f
      @service.poll
      payload = {
        :name => 'eagle',
        :bucket => :request,
        :start_timestamp => t0,
        :duration => Time.now.to_f-t0,
        :thread => @threads.sample
      }
      @service.on_transaction_finished(payload)
    end
    @service.unsubscribe('eagle')
  end

  def test_generating_traces
    require 'new_relic/agent/threading/thread_profile'

    measure do
      profile = ::NewRelic::Agent::Threading::ThreadProfile.new({})

      aggregate_lots_of_nodes(profile, 5, [])

      profile.generate_traces
    end
  end

  def aggregate_lots_of_nodes(profile, depth, trace)
    if depth > 0
      7.times do |i|
        trace.push("path#{i}:#{i+50}:in `depth#{depth}'")
        aggregate_lots_of_nodes(profile, depth-1, trace)
        trace.pop
      end
    else
      profile.aggregate(trace, :request, Thread.current)
    end
  end
end
