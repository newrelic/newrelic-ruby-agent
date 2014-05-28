# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class TestWorker
  include Sidekiq::Worker

  sidekiq_options :queue => SidekiqServer.instance.queue_name

  @jobs = {}
  @done_signal = ConditionVariable.new
  @mutex = Mutex.new

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
    @jobs[key] ||= []
    @jobs[key] << val
    @done_signal.signal if val == @done_at
  end

  def self.records_for(key)
    @jobs[key]
  end

  def self.wait
    @mutex.synchronize do
      @done_signal.wait(@mutex, 1)
    end
  end

  def perform(key, val)
    TestWorker.record(key, val)
  end
end
