# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative "sidekiq_server"

class TestWorker
  include Sidekiq::Worker

  sidekiq_options :queue => SidekiqServer.instance.queue_name, :retry => false
  @jobs = {}
  @jobs_mutex = Mutex.new

  @done = Queue.new

  def self.register_signal(key)
    @jobs_mutex.synchronize do
      return if @registered_signal

      NewRelic::Agent.subscribe(:transaction_finished) do |payload|
        @done.push(true)
      end
      @registered_signal = true
    end
  end

  def self.run_jobs(count)
    reset(count)
    count.times do |i|
      yield i
    end
    wait
  end

  def self.reset(done_at)
    @jobs_mutex.synchronize do 
      @jobs = {}
      @done_at = done_at
    end
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
    Timeout.timeout(15) do
      @done_at.times do
        @done.pop
        sleep(0.01)
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
