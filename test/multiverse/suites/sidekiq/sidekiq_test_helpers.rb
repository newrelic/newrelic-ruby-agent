# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'sidekiq'
require 'sidekiq/cli'
require 'newrelic_rpm'

class NRDeadEndJob
  # TODO: MAJOR VERSION - remove this when Sidekiq v5 is no longer supported
  if Sidekiq::VERSION.split('.').first.to_i >= 6
    include Sidekiq::Job
  else
    include Sidekiq::Worker
  end

  sidekiq_options retry: 5

  COMPLETION_VAR = :@@nr_job_complete
  ERROR_MESSAGE = 'kaboom'

  def perform(*args)
    raise ERROR_MESSAGE if args.first.is_a?(Hash) && args.first['raise_error']
  ensure
    self.class.class_variable_set(COMPLETION_VAR, true)
  end
end

module SidekiqTestHelpers
  def run_job(*args)
    segments = nil
    in_transaction do |txn|
      NRDeadEndJob.perform_async(*args)
      process_queued_jobs
      segments = txn.segments.select { |s| s.name.eql?('Nested/OtherTransaction/SidekiqJob/NRDeadEndJob/perform') }
    end

    assert_equal 1, segments.size, "Expected to find a single Sidekiq job segment, found #{segments.size}"
    segments.first
  end

  def run_job_and_get_attributes(*args)
    run_job(*args).attributes.agent_attributes_for(NewRelic::Agent::AttributeFilter::DST_TRANSACTION_TRACER)
  end

  def process_queued_jobs
    NRDeadEndJob.class_variable_set(NRDeadEndJob::COMPLETION_VAR, false)
    base_config = cli.instance_variable_defined?(:@config) ? cli.instance_variable_get(:@config) : Sidekiq.options

    config = base_config.dup # Create a mutable copy of the config to avoid FrozenError

    if defined?(JRuby)
      config[:concurrency] = 1 # Reduce concurrency for JRuby
      config[:timeout] = 30 # Increase timeout for slower JRuby processing
    end

    # TODO: MAJOR VERSION - remove this when Sidekiq v5 is no longer supported
    require 'sidekiq/launcher' if Sidekiq::VERSION.split('.').first.to_i < 6

    launcher = Sidekiq::Launcher.new(config)
    launcher.run
    
    timeout_duration = defined?(JRuby) ? 30 : 5 # JRuby needs more time due to different threading model
    sleep_interval = defined?(JRuby) ? 0.1 : 0.01 # Longer sleep intervals for JRuby
    Timeout.timeout(timeout_duration) do
      sleep sleep_interval until NRDeadEndJob.class_variable_get(NRDeadEndJob::COMPLETION_VAR)
    end

    # TODO: MAJOR VERSION - Sidekiq v7 is fine with launcher.stop, but v5 and v6
    #                       need the Manager#quiet call
    if launcher.instance_variable_defined?(:@manager)
      launcher.instance_variable_get(:@manager).quiet
    else
      launcher.stop
    end
  end

  def cli
    @@cli ||= begin
      cli = Sidekiq::CLI.instance
      cli.parse(['--require', File.absolute_path(__FILE__), '--queue', 'default,1'])
      cli.logger.instance_variable_get(:@logdev).instance_variable_set(:@dev, File.new('/dev/null', 'w'))
      ensure_sidekiq_config(cli)
      cli
    end
  end

  def ensure_sidekiq_config(cli)
    return unless Sidekiq::VERSION.split('.').first.to_i >= 7
    return unless cli.respond_to?(:config)
    return unless cli.config.nil?

    require 'sidekiq/config'
    cli.instance_variable_set(:@config, ::Sidekiq::Config.new)
  end

  def flatten(object)
    NewRelic::Agent::AttributeProcessing.flatten_and_coerce(object, 'job.sidekiq.args')
  end
end
