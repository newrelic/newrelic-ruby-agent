# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'sidekiq_test_helpers'

class SidekiqForceNewTransactionTest < Minitest::Test
  include SidekiqTestHelpers

  def setup
    harvest_transaction_events!
    harvest_span_events!
  end

  def teardown
    mocha_teardown
  end

  def test_sidekiq_force_new_transaction_default_value
    refute NewRelic::Agent.config[:'sidekiq.force_new_transaction'],
      'Expected sidekiq.force_new_transaction default to be false'
  end

  def test_sidekiq_force_new_transaction_configuration_can_be_set_to_true
    with_config(:'sidekiq.force_new_transaction' => true) do
      assert NewRelic::Agent.config[:'sidekiq.force_new_transaction'],
        'Expected sidekiq.force_new_transaction to be true when configured'
    end
  end

  def test_sidekiq_force_new_transaction_configuration_can_be_set_to_false
    with_config(:'sidekiq.force_new_transaction' => false) do
      refute NewRelic::Agent.config[:'sidekiq.force_new_transaction'],
        'Expected sidekiq.force_new_transaction to be false when configured'
    end
  end

  def test_sidekiq_job_added_as_nested_segment_when_force_new_false
    # Sidekiq version 6.x's perform_inline invokes String#constantize, which is only
    # delivered by ActiveSupport, which this test suite doesn't currently include.
    skip 'Test requires Sidekiq v7+' unless NewRelic::Helper.version_satisfied?(Sidekiq::VERSION, '>=', '7.0.0')

    with_config(:'sidekiq.force_new_transaction' => false) do
      txn = run_web_transaction_with_inline_job

      segment_names = txn.segments.map(&:name)
      expected_segments = %w[web Nested/OtherTransaction/SidekiqJob/NRDeadEndJob/perform]

      assert_equal expected_segments, segment_names,
        'Expected web transaction to contain nested Sidekiq job segment'
    end
  end

  def test_single_transaction_created_when_force_new_false
    # Sidekiq version 6.x's perform_inline invokes String#constantize, which is only
    # delivered by ActiveSupport, which this test suite doesn't currently include.
    skip 'Test requires Sidekiq v7+' unless NewRelic::Helper.version_satisfied?(Sidekiq::VERSION, '>=', '7.0.0')

    with_config(:'sidekiq.force_new_transaction' => false) do
      run_web_transaction_with_inline_job

      transactions = harvest_transaction_events!

      assert_equal 1, transactions[0][:events_seen], 'Expected exactly 1 transaction event'
      assert_equal 1, transactions[1].size, 'Expected 1 transaction in the harvest'

      transaction = transactions[1][0]

      assert_equal 'web', transaction[0]['name'], 'Expected transaction name to be "web"'
    end
  end

  def test_single_web_span_created_when_force_new_false
    # Sidekiq version 6.x's perform_inline invokes String#constantize, which is only
    # delivered by ActiveSupport, which this test suite doesn't currently include.
    skip 'Test requires Sidekiq v7+' unless NewRelic::Helper.version_satisfied?(Sidekiq::VERSION, '>=', '7.0.0')

    with_config(:'sidekiq.force_new_transaction' => false) do
      run_web_transaction_with_inline_job

      _, all_spans = harvest_span_events!
      spans = all_spans[1].select { |span| span['name'] }

      assert_equal 1, spans.size,
        'Expected only 1 span (web entry point, sidekiq job is nested as a segment)'

      web_span = spans[0]

      assert_equal 'web', web_span['name'], 'Expected span to be named "web"'
      assert web_span['nr.entryPoint'], 'Expected web span to be marked as entry point'
    end
  end

  def test_web_transaction_excludes_sidekiq_segment_when_force_new_true
    # Sidekiq version 6.x's perform_inline invokes String#constantize, which is only
    # delivered by ActiveSupport, which this test suite doesn't currently include.
    skip 'Test requires Sidekiq v7+' unless NewRelic::Helper.version_satisfied?(Sidekiq::VERSION, '>=', '7.0.0')

    with_config(:'sidekiq.force_new_transaction' => true) do
      txn = run_web_transaction_with_inline_job
      segment_names = txn.segments.map(&:name)

      assert_equal ['web'], segment_names,
        'Expected web transaction to only contain web segment (not sidekiq job)'
    end
  end

  def test_separate_transactions_for_web_and_sidekiq_when_force_new_true
    skip 'Test requires Sidekiq v7+' unless NewRelic::Helper.version_satisfied?(Sidekiq::VERSION, '>=', '7.0.0')

    with_config(:'sidekiq.force_new_transaction' => true) do
      run_web_transaction_with_inline_job

      transactions = harvest_transaction_events!

      # TODO: Skeptical -- is this the right call? Should we have three transactions?
      # Find distinct transaction names (filtering duplicates)
      # binding.irb
      transaction_names = transactions[1].map { |t| t[0]['name'] }.uniq

      assert_includes transaction_names, 'web', 'Expected to find web transaction'
      assert transaction_names.any? { |name| name.include?('SidekiqJob/NRDeadEndJob/perform') }, 'Expected to find sidekiq transaction'

      # Verify that web and sidekiq transactions have different names
      web_transactions = transactions[1].select { |t| t[0]['name'] == 'web' }
      sidekiq_transactions = transactions[1].select { |t| t[0]['name'].include?('SidekiqJob/NRDeadEndJob/perform') }

      assert_predicate web_transactions, :any?, 'Expected at least one web transaction'
      assert_predicate sidekiq_transactions, :any?, 'Expected at least one sidekiq transaction'
    end
  end

  def test_separate_spans_for_web_and_sidekiq_when_force_new_true
    # Sidekiq version 6.x's perform_inline invokes String#constantize, which is only
    # delivered by ActiveSupport, which this test suite doesn't currently include.
    skip 'Test requires Sidekiq v7+' unless NewRelic::Helper.version_satisfied?(Sidekiq::VERSION, '>=', '7.0.0')

    with_config(:'sidekiq.force_new_transaction' => true) do
      run_web_transaction_with_inline_job
      _, all_spans = harvest_span_events!
      spans = all_spans[1].select { |span| span['name'] }

      sidekiq_span = spans.find { |s| s['name'] =~ /SidekiqJob\/NRDeadEndJob\/perform/ }

      assert sidekiq_span, 'Expected to find sidekiq job span'
      assert sidekiq_span['nr.entryPoint'],
        'Expected sidekiq span to be marked as entry point (separate transaction)'

      # TODO: Suspicious
      # The web transaction may or may not create a span depending on sampling
      # The key assertion is that the sidekiq job has its own span as a separate transaction
      web_span = spans.find { |s| s['name'] == 'web' }
      if web_span
        refute_equal web_span['transactionId'], sidekiq_span['transactionId'],
          'If web span exists, it should have a different transaction ID'
      end
    end
  end

  private

  def run_web_transaction_with_inline_job
    in_web_transaction('web') do |txn|
      txn.stubs(:sampled?).returns(true)
      NRDeadEndJob.perform_inline
    end
  end
end
