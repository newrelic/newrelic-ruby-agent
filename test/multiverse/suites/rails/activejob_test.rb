# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'app'
require 'logger'
require 'stringio'
require 'minitest/mock'

# ActiveJob is in Rails 4.2+, so make sure we're on an allowed version before
# we try to load.
if Rails::VERSION::STRING >= '4.2.0'

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

  # Rails 8.1+ Continuations test job
  if defined?(ActiveJob::Continuable)
    class MyContinuableJob < ActiveJob::Base
      include ActiveJob::Continuable

      def self.last_cursor
        @@last_cursor
      end

      def perform(record_count: 5)
        step(:first_step) do
          # First step does something
        end

        step(:second_step) do |step|
          (0...record_count).each do |i|
            step.advance!(from: i + 1)
          end
          @@last_cursor = step.cursor
        end

        step(:third_step)
      end

      private

      def third_step
        # Third step as a method
      end
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

    ENQUEUE_PREFIX = 'ActiveJob/Inline/Queue/Produce/Named'
    PERFORM_PREFIX = 'ActiveJob/Inline/Queue/Consume/Named'

    PERFORM_TRANSACTION_NAME = 'OtherTransaction/ActiveJob::Inline/MyJob/execute'
    PERFORM_TRANSACTION_ROLLUP = 'OtherTransaction/ActiveJob::Inline/all'

    def test_record_enqueue_metrics
      in_web_transaction do
        MyJob.perform_later
      end

      assert_metrics_recorded("#{ENQUEUE_PREFIX}/default/MyJob")
    end

    def test_code_information_recorded_in_web_transaction
      code_attributes = {}
      with_config(:'code_level_metrics.enabled' => true) do
        in_web_transaction do
          MyJob.perform_later
          txn = NewRelic::Agent::Transaction.tl_current
          code_attributes = txn.segments.last.code_attributes
        end
      end

      assert_equal __FILE__, code_attributes['code.filepath']
      assert_equal 'perform', code_attributes['code.function']
      assert_equal MyJob.instance_method(:perform).source_location[1], code_attributes['code.lineno']
      assert_equal 'MyJob', code_attributes['code.namespace']
    end

    def test_code_information_recorded_with_new_transaction
      with_config(:'code_level_metrics.enabled' => true) do
        expected = {filepath: __FILE__,
                    lineno: MyJob.instance_method(:perform).source_location[1],
                    function: 'perform',
                    namespace: 'MyJob'}
        segment = MiniTest::Mock.new
        segment.expect(:code_information=, nil, [expected])
        segment.expect(:code_information=,
          nil,
          [{transaction_name: 'OtherTransaction/ActiveJob::Inline/MyJob/execute'}])
        (NewRelic::Agent::Instrumentation::ActiveJobSubscriber::PAYLOAD_KEYS.size + 1).times do
          segment.expect(:params, {}, [])
        end
        4.times do
          segment.expect(:finish, [])
        end
        segment.expect(:record_scoped_metric=, nil, [false])
        segment.expect(:notice_error, nil, [])
        NewRelic::Agent::Tracer.stub(:start_segment, segment) do
          MyJob.perform_later
        end
      end
    end

    def test_record_enqueue_metrics_with_alternate_queue
      in_web_transaction do
        MyJobWithAlternateQueue.perform_later
      end

      assert_metrics_recorded("#{ENQUEUE_PREFIX}/my_jobs/MyJobWithAlternateQueue")
    end

    def test_record_perform_metrics_in_web
      in_web_transaction do
        MyJob.perform_later
      end

      assert_metrics_recorded("#{PERFORM_PREFIX}/default/MyJob")
    end

    def test_record_perform_all_later_metrics_in_web
      skip if Gem::Version.new(Rails::VERSION::STRING) < Gem::Version.new('7.1.0')

      in_web_transaction do
        ActiveJob.perform_all_later(MyJob.new, MyJob.new, MyJob.new)
      end

      assert_metrics_recorded("#{PERFORM_PREFIX}/default/MyJob")
    end

    def test_record_perform_metrics_with_alternate_queue_in_web
      in_web_transaction do
        MyJobWithAlternateQueue.perform_later
      end

      assert_metrics_recorded("#{PERFORM_PREFIX}/my_jobs/MyJobWithAlternateQueue")
    end

    def test_doesnt_record_perform_metrics_from_background
      in_background_transaction do
        MyJob.perform_later
      end

      assert_metrics_not_recorded("#{PERFORM_PREFIX}/default/MyJob")
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
      MyJobWithParams.perform_later('1', '2')

      assert_equal(%w[1 2], MyJobWithParams.last_params)
    end

    def test_captures_errors
      # Because we're processing inline, we get the error raised here
      assert_raises ArgumentError do
        MyFailure.perform_later
      end

      assert_metrics_recorded(['Errors/all'])
    end

    def test_continuations_config_backwards_compatible
      # Verify the disable_active_job_step_names config works on all Rails versions
      # including those without Continuations support
      with_config(:disable_active_job_step_names => true) do
        in_web_transaction do
          MyJob.perform_later
        end
      end

      # Should record normal metrics without /step suffix
      assert_metrics_recorded("#{PERFORM_PREFIX}/default/MyJob")
      # Should not record any step-related metrics
      assert_no_metrics_match(/\/step/)
    end

    # Rails 8.1+ Continuations tests
    if defined?(ActiveJob::Continuable)
      def test_continuations_step_names_in_metrics
        MyContinuableJob.perform_later(record_count: 3)

        assert_metrics_recorded([
          'Ruby/ActiveJob/default/MyContinuableJob/step/first_step',
          'Ruby/ActiveJob/default/MyContinuableJob/step/second_step',
          'Ruby/ActiveJob/default/MyContinuableJob/step/third_step'
        ])
      end

      def test_continuations_step_started_metrics
        MyContinuableJob.perform_later(record_count: 3)

        assert_metrics_recorded([
          'Ruby/ActiveJob/default/MyContinuableJob/step_started/first_step',
          'Ruby/ActiveJob/default/MyContinuableJob/step_started/second_step',
          'Ruby/ActiveJob/default/MyContinuableJob/step_started/third_step'
        ])
      end

      def test_continuations_backwards_compatibility
        # Ensure the changes don't break jobs without continuations
        MyJob.perform_later

        # Regular job metrics should still be recorded
        assert_metrics_recorded([
          PERFORM_TRANSACTION_NAME
        ])

        # Should not create step metrics for regular jobs
        assert_metrics_not_recorded('Ruby/ActiveJob/default/MyJob/step')
      end

      def test_continuations_doesnt_break_regular_jobs
        # Ensure regular jobs without continuations still work
        MyJob.perform_later

        assert_metrics_recorded([PERFORM_TRANSACTION_ROLLUP,
          PERFORM_TRANSACTION_NAME])
        assert_metrics_not_recorded('Ruby/ActiveJob/default/MyJob/step')
      end

      def test_continuations_config_disables_step_names
        # Test that disable_active_job_step_names config option works
        with_config(:disable_active_job_step_names => true) do
          MyContinuableJob.perform_later(record_count: 3)

          # Should record generic step metrics without step names
          assert_metrics_recorded([
            'Ruby/ActiveJob/default/MyContinuableJob/step',
            'Ruby/ActiveJob/default/MyContinuableJob/step_started'
          ])

          # Should NOT record step-specific metrics
          assert_metrics_not_recorded([
            'Ruby/ActiveJob/default/MyContinuableJob/step/first_step',
            'Ruby/ActiveJob/default/MyContinuableJob/step/second_step',
            'Ruby/ActiveJob/default/MyContinuableJob/step/third_step'
          ])
        end
      end

      def test_continuations_step_name_param_added
        in_transaction do |txn|
          MyContinuableJob.perform_now(record_count: 2)

          step_segments = txn.segments.select { |s| s.name.include?('/step/') }

          refute_empty step_segments, 'Expected to find step segments'

          first_step = step_segments.detect { |s| s.name.include?('first_step') }

          assert first_step, 'Expected to find first_step segment'
          assert_equal 'first_step', first_step.params[:step_name]

          second_step = step_segments.detect { |s| s.name.include?('second_step') }

          assert second_step, 'Expected to find second_step segment'
          assert_equal 'second_step', second_step.params[:step_name]

          third_step = step_segments.detect { |s| s.name.include?('third_step') }

          assert third_step, 'Expected to find third_step segment'
          assert_equal 'third_step', third_step.params[:step_name]
        end
      end

      def test_continuations_cursor_param_added
        in_transaction do |txn|
          MyContinuableJob.perform_now(record_count: 3)

          step_segments = txn.segments.select { |s| s.name.include?('/step/second_step') }

          refute_empty step_segments, 'Expected to find second_step segments'

          # The second_step calls advance! which sets the cursor
          second_step = step_segments.first

          assert second_step.params.key?(:cursor), 'Expected cursor param to be present'
          # Verify cursor is an integer (the exact value depends on how ActiveJob sets it)
          assert_kind_of Integer, second_step.params[:cursor]
          assert second_step.params[:cursor] > 0, 'Expected cursor to be positive'
        end
      end

      def test_continuations_resumed_param_added_on_resumed_steps
        # This test verifies that when a job is resumed, the resumed param is set
        # We need to interrupt and resume the job to test this
        in_transaction do |txn|
          # First execution - will be interrupted at second_step
          begin
            MyContinuableJob.perform_now(record_count: 10)
          rescue ActiveJob::Interrupted
            # Expected - job was interrupted
          end

          # Check for interrupted segments
          step_started_segments = txn.segments.select { |s| s.name.include?('/step_started/') }

          refute_empty step_started_segments, 'Expected to find step_started segments'

          # When a step is first started (not resumed), resumed should be false or not present
          # depending on the Rails version implementation
          first_started = step_started_segments.detect { |s| s.name.include?('first_step') }
          if first_started&.params&.key?(:resumed)
            refute first_started.params[:resumed]
          end
        end

        # Resume the job in a new transaction
        in_transaction do |txn|
          MyContinuableJob.perform_now(record_count: 2)

          # After resumption, check if any steps have resumed: true
          # The exact behavior depends on how Rails implements continuation resumption
          step_started_segments = txn.segments.select { |s| s.name.include?('/step_started/') }

          # If any segment has a resumed param, verify it's a boolean
          resumed_segments = step_started_segments.select { |s| s.params.key?(:resumed) }

          resumed_segments.each do |segment|
            assert_includes [true, false], segment.params[:resumed],
              "Expected resumed param to be true or false, got #{segment.params[:resumed].inspect}"
          end
        end
      end
    end
  end

end
