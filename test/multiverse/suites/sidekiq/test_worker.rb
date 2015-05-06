# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class TestWorker
  include Sidekiq::Worker

  sidekiq_options :queue => SidekiqServer.instance.queue_name, :retry => false
  @jobs = {}
  @jobs_mutex = Mutex.new

  @done = Queue.new

  def self.register_signal(key)
    return if @registered_signal

    NewRelic::Agent.subscribe(:transaction_finished) do |payload|
      @done.push(true)
    end
    @registered_signal = true
  end

  def self.run_jobs(count)
    reset(count)
    count.times do |i|
      yield i
    end
    wait
  end

  def self.reset(done_at)
    @jobs = {}
    @done_at = done_at
  end

  def self.record(key, val)
    @jobs_mutex.synchronize do
      @jobs[key] ||= []
      @jobs[key] << val
    end
  end

  def self.records_for(key)
    @jobs[key]
  end

  def self.wait
    # Don't hang out forever, but shouldn't count on the timeout functionally
    Timeout.timeout(60) do
      @done_at.times do
        @done.pop
      end
    end
  end

  def self.fail=(val)
    @fail = val
  end

  def self.am_i_a_failure?
    @fail
  end

  def perform(key, val)
    if self.class.am_i_a_failure?
      raise "Uh oh"
    else
      TestWorker.record(key, val)
    end
  end
end
