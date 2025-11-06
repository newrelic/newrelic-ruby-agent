# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'sidekiq_test_helpers'

# On startup, Sidekiq instrumentation registers error and death handlers
# based on the value of the 'sidekiq.ignore_retry_errors'. Because of this,
# we need to have separate enabled/disabled test suites to test both cases.
class SidekiqIgnoreRetryErrorEnabledTest < Minitest::Test
  include SidekiqTestHelpers

    def setup
      @config = {:'sidekiq.ignore_retry_errors' => true}
      NewRelic::Agent.config.add_config_for_testing(@config)
    end

    def teardown
      NewRelic::Agent.config.reset_to_defaults
    end

    def test_error_handlers_not_registered_when_sidekiq_ignore_retry_errors_is_true
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

    def test_death_handlers_registered_when_sidekiq_ignore_retry_errors_is_true
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

      assert nr_death_handler_found,
        'Expected NewRelic death_handler to be registered when sidekiq.ignore_retry_errors is true'
    end

    def test_basic_job_execution_still_works
    segment = run_job

    assert_predicate segment, :finished?
    assert_predicate segment, :record_metrics?
    assert segment.duration.is_a?(Float)
  end
end
