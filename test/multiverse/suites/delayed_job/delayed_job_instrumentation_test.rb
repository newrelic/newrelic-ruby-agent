# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

if defined? Delayed::Backend::ActiveRecord
  class DelayedJobInstrumentationTest < Minitest::Test
    include MultiverseHelpers

    class QuackJob
      def initialize(index)
        @index = index
      end

      def display_name
        "Quack Job: #{@index}"
      end

      def perform
        puts "Performing Quack Job #{@index} .."
      end
    end

    setup_and_teardown_agent

    def after_setup
      # We set Delayed::Worker.delay_jobs = false in the before_suite to run jobs inline
      # for testing purposes, but we unfortunately hook the initialize method on Delayed::Worker
      # to install our instrumentation.  Delayed::Workers are not initialized by when running
      # tests inline so we have to manually instantiate one that we don't use to get our
      # instrumentation installed.
      Delayed::Worker.new
    end

    def test_enqueue_standalone_job
      job = QuackJob.new rand(100)
      invoke_job(job)

      assert_metrics_recorded [
        'OtherTransaction/all',
        'OtherTransaction/DelayedJob/all',
        'OtherTransaction/DelayedJob/DelayedJobInstrumentationTest::QuackJob'
      ]
    end

    # Note we use this method instead of Delayed::Job.enqueue because DJ 2.1.4 does not call
    # invoke_job when running jobs inline it instead calls perform directly.
    def invoke_job(job)
      job = Delayed::Job.new(:payload_object => job)
      job.invoke_job
    end
  end
end
