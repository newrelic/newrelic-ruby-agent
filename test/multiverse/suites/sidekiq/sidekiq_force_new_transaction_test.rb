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

  def test_sidekiq_job_added_to_existing_web_transaction_when_false
    # Sidekiq version 6.x's perform_inline invokes String#constantize, which is only
    # delivered by ActiveSupport, which this test suite doesn't currently include.
    skip 'Test requires Sidekiq v7+' unless NewRelic::Helper.version_satisfied?(Sidekiq::VERSION, '>=', '7.0.0')

    with_config(:'sidekiq.force_new_transaction' => false) do
      config = if Sidekiq::VERSION.split('.').first.to_i >= 7
        Sidekiq.default_configuration
      else
        Sidekiq
      end

      t = in_web_transaction('web') do |txn|
        NRDeadEndJob.perform_inline
      end

      segment_names = t.segments.map(&:name)

      assert_equal %w[web Nested/OtherTransaction/SidekiqJob/NRDeadEndJob/perform], segment_names

      transactions = harvest_transaction_events!

      assert_equal 1, transactions[0][:events_seen]
      assert_equal 1, transactions[1].size

      first_transaction = transactions[1][0]
      assert_equal 'web', first_transaction[0]['name']

      _, spans = harvest_span_events!

      assert_equal 2, spans[1].size
      assert_equal 'web', spans[1][0]['name']
      assert spans[1][0]['nr.entryPoint']

      assert 'Nested/OtherTransaction/SidekiqJob/NRDeadEndJob/perform', spans[1][0]['name']
      assert_equal spans[1][0]['transactionId'], spans[1][1]['transactionId']
    end
  end

  def test_sidekiq_job_not_added_to_existing_web_transaction_when_true
    # Sidekiq version 6.x's perform_inline invokes String#constantize, which is only
    # delivered by ActiveSupport, which this test suite doesn't currently include.
    skip 'Test requires Sidekiq v7+' unless NewRelic::Helper.version_satisfied?(Sidekiq::VERSION, '>=', '7.0.0')

    with_config(:'sidekiq.force_new_transaction' => true) do
      config = if Sidekiq::VERSION.split('.').first.to_i >= 7
        Sidekiq.default_configuration
      else
        Sidekiq
      end

      t = in_web_transaction('web') do |txn|
        txn.stubs(:sampled?).returns(true)
        NRDeadEndJob.perform_inline
      end

      transactions = harvest_transaction_events!

      assert_equal 2, transactions[0][:events_seen]
      assert_equal 2, transactions[1].size

      first_transaction = transactions[1][0]
      assert_equal 'web', first_transaction['name']

      second_transaction = transactions[1][1]
      assert_equal 'Nested/OtherTransaction/SidekiqJob/NRDeadEndJob/perform', second_transaction['name']

      _, spans = harvest_span_events!

      assert_equal 2, spans[1].size
      assert_equal 'web', spans[1][1]['name']
      assert spans[1][1]['nr.entryPoint']

      assert 'Nested/OtherTransaction/SidekiqJob/NRDeadEndJob/perform', spans[1][0]['name']
      assert_equal spans[1][0]['transactionId'], spans[1][1]['transactionId']
    end
  end
end
