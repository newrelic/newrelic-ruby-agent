# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'sidekiq_test_helpers'

class SidekiqIgnoreRetryErrorsTest < Minitest::Test
  include SidekiqTestHelpers

  def test_sidekiq_ignore_retry_errors_default_value
    refute NewRelic::Agent.config[:'sidekiq.ignore_retry_errors'],
      'Expected sidekiq.ignore_retry_errors default to be false'
  end

  def test_sidekiq_ignore_retry_errors_configuration_can_be_set_to_true
    with_config(:'sidekiq.ignore_retry_errors' => true) do
      assert NewRelic::Agent.config[:'sidekiq.ignore_retry_errors'],
        'Expected sidekiq.ignore_retry_errors to be true when configured'
    end
  end

  def test_sidekiq_ignore_retry_errors_configuration_can_be_set_to_false
    with_config(:'sidekiq.ignore_retry_errors' => false) do
      refute NewRelic::Agent.config[:'sidekiq.ignore_retry_errors'],
        'Expected sidekiq.ignore_retry_errors to be false when configured'
    end
  end

  def test_error_handlers_registered_when_sidekiq_ignore_retry_errors_is_false
    # TODO: MAJOR VERSION - remove this when Sidekiq v5 is no longer supported
    skip 'Test requires Sidekiq v6+' unless Sidekiq::VERSION.split('.').first.to_i >= 6

    config = if Sidekiq::VERSION.split('.').first.to_i >= 7
      Sidekiq.default_configuration
    else
      Sidekiq
    end

    error_handlers = if config.respond_to?(:error_handlers)
      config.error_handlers
    else
      config[:error_handlers] || []
    end

    nr_error_handler_found = error_handlers.any? do |handler|
      handler.is_a?(Proc) && handler.source_location&.first&.include?('newrelic')
    end

    assert nr_error_handler_found,
      'Expected NewRelic error_handler to be registered when sidekiq.ignore_retry_errors is false'
  end

  def test_error_handlers_not_registered_when_sidekiq_ignore_retry_errors_is_true
    with_config(:'sidekiq.ignore_retry_errors' => true) do
      # TODO: MAJOR VERSION - remove this when Sidekiq v5 is no longer supported
      skip 'Test requires Sidekiq v6+' unless Sidekiq::VERSION.split('.').first.to_i >= 6

      config = if Sidekiq::VERSION.split('.').first.to_i >= 7
        Sidekiq.default_configuration
      else
        Sidekiq
      end

      error_handlers = if config.respond_to?(:error_handlers)
        config.error_handlers
      else
        config[:error_handlers] || []
      end

      nr_error_handler_found = error_handlers.any? do |handler|
        handler.is_a?(Proc) && handler.source_location&.first&.include?('newrelic')
      end

      refute nr_error_handler_found,
        'Expected NewRelic error_handler to NOT be registered when sidekiq.ignore_retry_errors is true'
    end
  end

  def test_death_handlers_registered_when_sidekiq_ignore_retry_errors_is_true
    with_config(:'sidekiq.ignore_retry_errors' => true) do
      # TODO: MAJOR VERSION - remove this when Sidekiq v5 is no longer supported
      skip 'Test requires Sidekiq v6+' unless Sidekiq::VERSION.split('.').first.to_i >= 6

      config = if Sidekiq::VERSION.split('.').first.to_i >= 7
        Sidekiq.default_configuration
      else
        Sidekiq
      end

      death_handlers = if config.respond_to?(:death_handlers)
        config.death_handlers
      else
        config[:death_handlers] || []
      end

      puts '**************************'
      puts "death_handlers: #{death_handlers.inspect}"

      nr_death_handler_found = death_handlers.any? do |handler|
        handler.is_a?(Proc) && handler.source_location&.first&.include?('newrelic')
      end

      puts "nr_death_handler_found: #{nr_death_handler_found}"

      puts "sidekiq.ignore_retry_errors: #{NewRelic::Agent.config[:'sidekiq.ignore_retry_errors']}"
      puts '**************************'

      assert nr_death_handler_found,
        'Expected NewRelic death_handler to be registered when sidekiq.ignore_retry_errors is true'
    end
  end

  def test_death_handlers_not_registered_when_sidekiq_ignore_retry_errors_is_false
    # TODO: MAJOR VERSION - remove this when Sidekiq v5 is no longer supported
    skip 'Test requires Sidekiq v6+' unless Sidekiq::VERSION.split('.').first.to_i >= 6

    config = if Sidekiq::VERSION.split('.').first.to_i >= 7
      Sidekiq.default_configuration
    else
      Sidekiq
    end

    death_handlers = if config.respond_to?(:death_handlers)
      config.death_handlers
    else
      config[:death_handlers] || []
    end

    nr_death_handler_found = death_handlers.any? do |handler|
      handler.is_a?(Proc) && handler.source_location&.first&.include?('newrelic')
    end

    refute nr_death_handler_found,
      'Expected NewRelic death_handler to NOT be registered when sidekiq.ignore_retry_errors is false'
  end

  def test_basic_job_execution_still_works
    with_config(:'sidekiq.ignore_retry_errors' => true) do
      segment = run_job

      assert_predicate segment, :finished?
      assert_predicate segment, :record_metrics?
      assert segment.duration.is_a?(Float)
    end
  end
end
