# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'sidekiq'
require 'sidekiq/cli'

class SidekiqServer
  include Singleton

  attr_reader :queue_name

  def initialize
    @queue_name = "sidekiq#{Process.pid}"
    @sidekiq = Sidekiq::CLI.instance
  end

  def run(file="test_worker.rb")
    @sidekiq.parse(["--require", File.join(File.dirname(__FILE__), file),
                    "--queue", "#{queue_name},1"])
    Thread.new { @sidekiq.run }
  end
end
