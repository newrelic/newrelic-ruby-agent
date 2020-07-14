# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'sidekiq'
require 'sidekiq/cli'

class SidekiqServer
  include Singleton

  THREAD_JOIN_TIMEOUT = 30

  attr_reader :queue_name

  def initialize
    @queue_name = "sidekiq#{Process.pid}"
    @sidekiq = Sidekiq::CLI.instance
  end

  def run(file="test_worker.rb")
    @sidekiq.parse(["--require", File.join(File.dirname(__FILE__), file),
                    "--queue", "#{queue_name},1"])
    @cli_thread = Thread.new { @sidekiq.run }
  end

  # If we just let the process go away, occasional timing issues cause the
  # Launcher actor in Sidekiq to throw a fuss and exit with a failed code.
  def stop
    puts "Trying to stop Sidekiq gracefully from #{$$}"
    Process.kill("INT", $$)
    if @cli_thread.join(THREAD_JOIN_TIMEOUT).nil?
      puts "#{$$} Sidekiq::CLI thread timeout on exit"
    end
  end
end
