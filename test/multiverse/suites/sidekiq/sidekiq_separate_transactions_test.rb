# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'sidekiq_test_helpers'

class SidekiqSeparateTransactionsTest < Minitest::Test
  include SidekiqTestHelpers

  def setup
    NewRelic::Agent.drop_buffered_data
    harvest_transaction_events!
  end

  def test_sidekiq_separate_transactions_default_is_false
    refute NewRelic::Agent.config[:'sidekiq.separate_transactions'],
      'Expected default value for sidekiq.separate_transactions to be false'
  end

  def test_default_behavior_nests_job_in_web_transaction
    skip 'This test requires Sidekiq v7+' unless NewRelic::Helper.version_satisfied?(Sidekiq::VERSION, '>=', '7.0.0')

    with_config(:'sidekiq.separate_transactions' => false) do
      web_txn = nil
      in_transaction(:category => :controller) do |txn|
        txn.stubs(:sampled?).returns(true)
        web_txn = txn
        NRDeadEndJob.perform_inline
      end

      segments = web_txn.segments.select { |s| s.name.include?('SidekiqJob') }

      assert_equal 1, segments.size, 'Expected Sidekiq job to be a nested segment'

      assert segments.first.name.start_with?('Nested/'),
        'Expected segment name to start with "Nested/"'
    end
  end

  def test_separate_transactions_creates_new_transaction_for_web_parent
    skip 'This test requires Sidekiq v7+' unless NewRelic::Helper.version_satisfied?(Sidekiq::VERSION, '>=', '7.0.0')

    with_config(:'sidekiq.separate_transactions' => true) do
      in_transaction('WebTransaction', :category => :controller) do |txn|
        txn.stubs(:sampled?).returns(true)
        NRDeadEndJob.perform_inline
      end

      events = harvest_transaction_events!
      transactions = events[1]

      assert_equal 2, transactions.size,
        "Expected 2 transactions (web and Sidekiq job), got #{transactions.size}"

      web_event = transactions[0][0] # First transaction's intrinsics
      job_event = transactions[1][0] # Second transaction's intrinsics

      assert_equal 'WebTransaction', web_event['name'],
        'First transaction should be the web transaction'

      assert_includes job_event['name'], 'SidekiqJob',
        "Second transaction should be a Sidekiq job, got: #{job_event['name']}"
    end
  end

  def test_separate_transactions_preserves_nested_behavior_for_background_parent
    skip 'This test requires Sidekiq v7+' unless NewRelic::Helper.version_satisfied?(Sidekiq::VERSION, '>=', '7.0.0')

    with_config(:'sidekiq.separate_transactions' => true) do
      background_txn = nil

      in_transaction(:category => :task) do |txn|
        txn.stubs(:sampled?).returns(true)
        background_txn = txn
        NRDeadEndJob.perform_inline
      end

      segments = background_txn.segments.select { |s| s.name.include?('SidekiqJob') }

      assert_equal 1, segments.size,
        'Expected Sidekiq job to remain a nested segment when parent is background transaction'

      assert segments.first.name.start_with?('Nested/'),
        'Expected segment name to start with "Nested/" for background parent'
    end
  end

  def test_separate_transactions_with_config_disabled_keeps_nested_behavior
    skip 'This test requires Sidekiq v7+' unless NewRelic::Helper.version_satisfied?(Sidekiq::VERSION, '>=', '7.0.0')

    with_config(:'sidekiq.separate_transactions' => false) do
      in_transaction('WebTransaction', :category => :controller) do |txn|
        txn.stubs(:sampled?).returns(true)
        NRDeadEndJob.perform_inline
      end

      events = harvest_transaction_events!
      transactions = events[1]

      assert_equal 1, transactions.size,
        'Expected 1 transaction when sidekiq.separate_transactions is false'

      web_event = transactions[0][0]

      assert_equal 'WebTransaction', web_event['name'],
        'Single transaction should be the web transaction'
    end
  end

  def test_separate_transactions_correct_metric_recording
    skip 'This test requires Sidekiq v7+' unless NewRelic::Helper.version_satisfied?(Sidekiq::VERSION, '>=', '7.0.0')

    with_config(:'sidekiq.separate_transactions' => true) do
      in_transaction('WebTransaction', :category => :controller) do |txn|
        txn.stubs(:sampled?).returns(true)
        NRDeadEndJob.perform_inline
      end

      assert_metrics_recorded([
        'OtherTransaction/SidekiqJob/NRDeadEndJob/perform'
      ])
    end
  end

  def test_web_transaction_duration_excludes_job_execution_time
    skip 'This test requires Sidekiq v7+' unless NewRelic::Helper.version_satisfied?(Sidekiq::VERSION, '>=', '7.0.0')

    job_sleep_duration = 0.2

    with_config(:'sidekiq.separate_transactions' => true) do
      original_perform = NRDeadEndJob.instance_method(:perform)
      NRDeadEndJob.define_method(:perform) do |*args|
        sleep(job_sleep_duration)
        original_perform.bind(self).call(*args)
      end

      begin
        in_transaction('WebTransaction', :category => :controller) do |txn|
          txn.stubs(:sampled?).returns(true)
          NRDeadEndJob.perform_inline
        end

        events = harvest_transaction_events!
        transactions = events[1]

        assert_equal 2, transactions.size,
          'Expected 2 transaction events'

        web_event = transactions[0][0] # First transaction's intrinsics
        job_event = transactions[1][0] # Second transaction's intrinsics

        web_duration = web_event['duration']
        job_duration = job_event['duration']

        assert_operator web_duration, :<, 0.1, "Web transaction duration (#{web_duration}s) should be < 0.1s, " \
          'but it appears to include job execution time'

        # Job transaction should include the sleep time (>= 200ms)
        assert_operator job_duration, :>=, job_sleep_duration * 0.9, "Job transaction duration (#{job_duration}s) should be >= #{job_sleep_duration}s"
      ensure
        # Restore original perform method
        NRDeadEndJob.define_method(:perform, original_perform)
      end
    end
  end
end
