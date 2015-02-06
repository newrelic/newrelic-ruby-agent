# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(__FILE__, '..', 'app'))

require 'logger'
require 'stringio'

# ActiveJob is in Rails 4.2+, so make sure we're on an allowed version before
# we try to load. Previously just tried to require it, but that had load issues
# on Rubinius.
if Rails::VERSION::STRING >= "4.2.0"

require 'active_job'

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

class MyFailure < ActiveJob::Base

  def perform
    raise ArgumentError.new("No it isn't!")
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
      puts "\nEmitting log from failure: #{self.name}"
      @log.rewind
      puts @log.read
    end
  end

  ENQUEUE_PREFIX = "MessageBroker/ActiveJob::Inline/Queue/Produce/Named"
  PERFORM_PREFIX = "MessageBroker/ActiveJob::Inline/Queue/Consume/Named"

  PERFORM_TRANSACTION_NAME   = 'OtherTransaction/ActiveJob::Inline/MyJob/execute'
  PERFORM_TRANSACTION_ROLLUP = 'OtherTransaction/ActiveJob::Inline/all'

  def test_record_enqueue_metrics
    in_web_transaction do
      MyJob.perform_later
    end

    assert_metrics_recorded("#{ENQUEUE_PREFIX}/default")
  end

  def test_record_enqueue_metrics_with_alternate_queue
    in_web_transaction do
      MyJobWithAlternateQueue.perform_later
    end

    assert_metrics_recorded("#{ENQUEUE_PREFIX}/my_jobs")
  end

  def test_record_perform_metrics_in_web
    in_web_transaction do
      MyJob.perform_later
    end

    assert_metrics_recorded("#{PERFORM_PREFIX}/default")
  end

  def test_record_perform_metrics_with_alternate_queue_in_web
    in_web_transaction do
      MyJobWithAlternateQueue.perform_later
    end

    assert_metrics_recorded("#{PERFORM_PREFIX}/my_jobs")
  end

  def test_doesnt_record_perform_metrics_from_background
    in_background_transaction do
      MyJob.perform_later
    end

    assert_metrics_not_recorded("#{PERFORM_PREFIX}/default")
  end

  def test_starts_transaction_if_there_isnt_one
    MyJob.perform_later
    assert_metrics_recorded([PERFORM_TRANSACTION_ROLLUP,
                             PERFORM_TRANSACTION_NAME])
  end

  def test_nests_other_transaction_if_already_running
    in_background_transaction do
      MyJob.perform_later
    end

    assert_metrics_recorded([PERFORM_TRANSACTION_ROLLUP,
                             PERFORM_TRANSACTION_NAME])
  end

  # If running tasks inline, either in a dev environment or from
  # misconfiguration we shouldn't accidentally rename our web transaction
  def test_doesnt_nest_transactions_if_in_web
    in_web_transaction do
      MyJob.perform_later
    end

    assert_metrics_not_recorded([PERFORM_TRANSACTION_ROLLUP,
                                 PERFORM_TRANSACTION_NAME])
  end

  def test_doesnt_interfere_with_params_on_job
    MyJobWithParams.perform_later("1", "2")
    assert_equal(["1", "2"], MyJobWithParams.last_params)
  end

  def test_captures_errors
    # Because we're processing inline, we get the error raised here
    assert_raises ArgumentError do
      MyFailure.perform_later
    end
    assert_metrics_recorded(["Errors/all"])
  end
end

end
