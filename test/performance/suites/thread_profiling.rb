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
    @service.subscribe(NewRelic::Agent::Threading::BacktraceService::ALL_TRANSACTIONS)
  end

  def teardown
    @service.unsubscribe(NewRelic::Agent::Threading::BacktraceService::ALL_TRANSACTIONS)
    @cvar.broadcast
    @threads.each(&:join)
  end

  def test_gather_backtraces
    (iterations / 10).times do
      @service.poll
    end
  end
end
