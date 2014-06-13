# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class TestWorker
  include Sidekiq::Worker

  sidekiq_options :queue => SidekiqServer.instance.queue_name

  @jobs = {}
  @jobs_mutex = Mutex.new

  @done_signal = ConditionVariable.new
  @done_mutex = Mutex.new

  def self.register_signal(key)
    return if @registered_signal

    NewRelic::Agent.subscribe(:transaction_finished) do |payload|
      if @jobs[key].count == @done_at
        @done_signal.signal
      end
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
    @done_mutex.synchronize do
      @done_signal.wait(@done_mutex, 1)
    end
  end

  def perform(key, val)
    TestWorker.record(key, val)
  end
end
