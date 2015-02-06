# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/delayed_job_injection'

if NewRelic::Agent::Samplers::DelayedJobSampler.supported_backend?
  class DelayedJobSamplerTest < Minitest::Test
    include MultiverseHelpers

    TestWorker = Struct.new(:name, :read_ahead)

    setup_and_teardown_agent do
      NewRelic::DelayedJobInjection.worker_name = "delayed"
      @worker = TestWorker.new("delayed", 1)
      @sampler = NewRelic::Agent::Samplers::DelayedJobSampler.new
    end

    def after_teardown
      # This appears in the base delayed_job gem even after the adapter split
      # so it appears to be safe to call across adapters
      Delayed::Job.delete_all
    end

    class IWantToWait
      def take_action
      end
    end

    def test_cant_create_without_injection
      NewRelic::DelayedJobInjection.worker_name = nil
      assert_raises(NewRelic::Agent::Sampler::Unsupported) do
        NewRelic::Agent::Samplers::DelayedJobSampler.new
      end
    end

    def test_sampler_no_failures_or_locks
      @sampler.poll

      assert_metrics_recorded(
        "Workers/DelayedJob/failed_jobs"      => { :total_call_time => 0 },
        "Workers/DelayedJob/locked_jobs"      => { :total_call_time => 0 })
    end

    def test_sampler_sees_failures
      job = IWantToWait.new.delay.take_action

      return unless job.respond_to?(:fail!)
      job.fail!

      @sampler.poll

      assert_metrics_recorded(
        "Workers/DelayedJob/failed_jobs" => { :total_call_time => 1 })
    end

    def test_sampler_sees_locks
      IWantToWait.new.delay.take_action
      ::Delayed::Job.reserve(@worker)

      @sampler.poll

      assert_metrics_recorded(
        "Workers/DelayedJob/locked_jobs" => { :total_call_time => 1 })
    end

    def test_sampler_queue_depth_with_job
      IWantToWait.new.delay.take_action

      @sampler.poll

      assert_metrics_recorded(
        "Workers/DelayedJob/queue_length/priority/0" => { :total_call_time => 1 },
        "Workers/DelayedJob/queue_length/all"        => { :total_call_time => 1 })
    end

    def test_sampler_queue_depth_with_alternate_priority
      IWantToWait.new.delay(:priority => 7).take_action

      @sampler.poll

      assert_metrics_recorded(
        "Workers/DelayedJob/queue_length/priority/7" => { :total_call_time => 1 },
        "Workers/DelayedJob/queue_length/all"        => { :total_call_time => 1 })
    end

    def test_sampler_queue_depth_with_default_queue
      return unless Delayed::Job.instance_methods.include?(:queue)

      IWantToWait.new.delay.take_action

      @sampler.poll

      assert_metrics_recorded(
        "Workers/DelayedJob/queue_length/name/default" => { :total_call_time => 1 },
        "Workers/DelayedJob/queue_length/all"          => { :total_call_time => 1 })
    end

    def test_sampler_queue_depth_with_alternate_queues
      return unless Delayed::Job.instance_methods.include?(:queue)

      IWantToWait.new.delay(:queue => "cue").take_action
      IWantToWait.new.delay(:queue => "cute").take_action

      @sampler.poll

      assert_metrics_recorded(
        "Workers/DelayedJob/queue_length/name/cue"   => { :total_call_time => 1 },
        "Workers/DelayedJob/queue_length/name/cute"  => { :total_call_time => 1 },
        "Workers/DelayedJob/queue_length/all"        => { :total_call_time => 2 })
    end

    def test_sampler_queue_depth_with_queues_and_priorities
      return unless Delayed::Job.instance_methods.include?(:queue)

      IWantToWait.new.delay(:priority => 1, :queue => "cue").take_action
      IWantToWait.new.delay(:priority => 1, :queue => "cute").take_action

      @sampler.poll

      assert_metrics_recorded(
        "Workers/DelayedJob/queue_length/name/cue"   => { :total_call_time => 1 },
        "Workers/DelayedJob/queue_length/name/cute"  => { :total_call_time => 1 },
        "Workers/DelayedJob/queue_length/priority/1" => { :total_call_time => 2 },
        "Workers/DelayedJob/queue_length/all"        => { :total_call_time => 2 })
    end
  end
end
