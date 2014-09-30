# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'multiverse_helpers'
require File.expand_path(File.join(__FILE__, '..', 'app'))

require 'logger'
require 'stringio'

# ActiveJob is in Rails 4.2+, so give it a shot and see whether we load
begin
  require 'active_job'
rescue LoadError
  # nope
end

if defined?(ActiveJob)

ActiveJob::Base.queue_adapter = :inline

class MyJob < ActiveJob::Base
  def perform
    # Nothing needed!
  end
end

class MyJobWithAlternateQueue < ActiveJob::Base
  queue_as :my_jobs

  def perform
  end
end

class MyJobWithParams < ActiveJob::Base
  def self.last_params
    @@last_params
  end

  def perform(first, last)
    @@last_params = [first, last]
  end
end

class ActiveJobTest < Minitest::Test

  include MultiverseHelpers

  setup_and_teardown_agent do
    @log = StringIO.new
    ActiveJob::Base.logger = ::Logger.new(@log)
  end

  def after_teardown
    unless passed?
      @log.rewind
      puts @log.read
    end
  end

  ENQUEUE_PREFIX = "MessageBroker/ActiveJob::Inline/Queue/Produce/Named"
  PERFORM_PREFIX = "MessageBroker/ActiveJob::Inline/Queue/Consume/Named"

  def test_record_enqueue_metrics
    MyJob.perform_later
    assert_metrics_recorded("#{ENQUEUE_PREFIX}/default")
  end

  def test_record_enqueue_metrics_with_alternate_queue
    MyJobWithAlternateQueue.perform_later
    assert_metrics_recorded("#{ENQUEUE_PREFIX}/my_jobs")
  end

  def test_record_perform_metrics
    MyJob.perform_later
    assert_metrics_recorded("#{PERFORM_PREFIX}/default")
  end

  def test_record_perform_metrics_with_alternate_queue
    MyJobWithAlternateQueue.perform_later
    assert_metrics_recorded("#{PERFORM_PREFIX}/my_jobs")
  end

  def test_doesnt_interfere_with_params_on_job
    MyJobWithParams.perform_later("1", "2")
    assert_equal(["1", "2"], MyJobWithParams.last_params)
  end
end

end
