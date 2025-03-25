# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'sidekiq'
require 'sidekiq/cli'
require 'newrelic_rpm'
require_relative 'app/models/dolce'

Sidekiq::DelayExtensions.enable_delay!

module SidekiqTestHelpers
  def run_job(*args)
    segments = nil
    in_transaction do |txn|
      d = Dolce.new
      d.delay.long_running_task
      process_queued_jobs
      segments = txn.segments.select { |s| s.name.eql?('Nested/OtherTransaction/SidekiqJob/Dolce/long_running_task') }
    end

    assert_equal 1, segments.size, "Expected to find a single Sidekiq job segment, found #{segments.size}"
    segments.first
  end

  def run_job_and_get_attributes(*args)
    run_job(*args).attributes.agent_attributes_for(NewRelic::Agent::AttributeFilter::DST_TRANSACTION_TRACER)
  end

  def process_queued_jobs
    Dolce.class_variable_set(Dolce::COMPLETION_VAR, false)
    config = cli.instance_variable_defined?(:@config) ? cli.instance_variable_get(:@config) : Sidekiq.options

    launcher = Sidekiq::Launcher.new(config)
    launcher.run
    Timeout.timeout(5) do
      sleep 0.01 until Dolce.class_variable_get(Dolce::COMPLETION_VAR)
    end

    launcher.stop
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
