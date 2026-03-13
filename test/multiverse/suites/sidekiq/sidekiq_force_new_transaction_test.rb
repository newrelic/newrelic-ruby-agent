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

  # TODO: Do we need to add active job to reproduce the behavior this feature intends to fix?
  # TODO: Do we need to add tests related to DT headers? Recheck what the customer's concern about that was
  # TODO: Are we able to use perform_action_with_newrelic_trace or do we need to use start_new_transaction?

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

      # Do I need these if I harvest?
      segment_names = t.segments.map(&:name)

      assert_equal %w[web Nested/OtherTransaction/SidekiqJob/NRDeadEndJob/perform], segment_names

      transactions = harvest_transaction_events!

      assert_equal 1, transactions[0][:events_seen]
      assert_equal 1, transactions[1].size

      first_transaction = transactions[1][0]
      # assert_equal 'web', first_transaction['name']

      spans = harvest_span_events!

      assert_equal 2, spans[1].size

      # other possible span assertions:
      # make sure the nr.entryPoint attribute is present on the web span
      # make sure it isn't on the sidekiq span
      # make sure the sidekiq span is the child of the web span
      # could make sure they all have the same transaction id
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

      segment_names = t.segments.map(&:name)

      assert_equal %w[web], segment_names
      # TODO: ADD MORE ASSERTIONS
    end
  end

  def test_sidekiq_job_part_of_new_transaction_when_true
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

      # Do I need to harvest?
      segment_names = t.segments.map(&:name)

      transactions = harvest_transaction_events!
      # TODO: ADD MORE ASSERTIONS
    end
  end
end
