# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

if defined?(Delayed::Backend::ActiveRecord) && Delayed::Worker.respond_to?(:delay_jobs)
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
        "Performing Quack Job #{@index} .."
      end
    end

    class Pelican < ActiveRecord::Base
      self.table_name = :pelicans

      def quack
        "quack..."
      end

      def quack_later
        "...quack"
      end

      handle_asynchronously :quack_later
    end

    setup_and_teardown_agent

    def after_setup
      Delayed::Worker.delay_jobs = false
      # We set Delayed::Worker.delay_jobs = false to run jobs inline for testing purposes, but
      # we unfortunately hook the initialize method on Delayed::Worker
      # to install our instrumentation.  Delayed::Workers are not initialized when running
      # tests inline so we have to manually instantiate one to install our instrumentation.
      # We also need to take care to only install the instrumentation once.
      unless Delayed::Job.instance_methods.any? { |m|  m == :invoke_job_without_new_relic || m == "invoke_job_without_new_relic" }
        Delayed::Worker.new
      end
    end

    def after_teardown
      Delayed::Worker.delay_jobs = true
    end

    # Delayed Job doesn't expose a version number, so we have to resort to checking Gem.loaded_specs.
    # Additionally, earlier versions of Delayed Job do not call invoke_job when running jobs inline.
    # We can only test methods using delay and handle_asynchronously on versions that run jobs via
    # the invoke_job method.
    def self.dj_invokes_job_inline?
      Gem.loaded_specs["delayed_job"].version >= Gem::Version.new("3.0.0")
    end

    if dj_invokes_job_inline?
      def test_delay_method
        p = Pelican.create(:name => "Charlie")
        p.delay.quack

        assert_metrics_recorded [
          'OtherTransaction/all',
          'OtherTransaction/DelayedJob/all',
          'OtherTransaction/DelayedJob/DelayedJobInstrumentationTest::Pelican#quack'
        ]
      end

      def test_handle_asynchronously
        p = Pelican.create(:name => "Charlieee")
        p.quack_later

        assert_metrics_recorded [
          'OtherTransaction/all',
          'OtherTransaction/DelayedJob/all',
          'OtherTransaction/DelayedJob/DelayedJobInstrumentationTest::Pelican#quack_later_without_delay'
        ]
      end
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

    # Note we use this method instead of Delayed::Job.enqueue because Delayed Job 2.1.4 does
    # not call invoke_job when running jobs inline it instead calls perform directly.  This
    # allows us to test the stand alone job case on all supported versions of Delayed Job.
    def invoke_job(job)
      job = Delayed::Job.new(:payload_object => job)
      job.invoke_job
    end
  end
end
