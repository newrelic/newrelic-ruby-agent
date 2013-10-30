# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'monitor'

require 'newrelic_rpm' unless defined?( NewRelic )
require 'new_relic/agent' unless defined?( NewRelic::Agent )

class NewRelic::Agent::RequestSampler
  include NewRelic::Coerce,
          MonitorMixin

  # The namespace and keys of config values
  MAX_SAMPLES_KEY  = :'analytics_events.max_samples_stored'
  ENABLED_KEY      = :'analytics_events.enabled'
  ENABLED_TXN_KEY  = :'analytics_events.transactions.enabled'

  # The type field of the sample
  SAMPLE_TYPE              = 'Transaction'

  # Strings for static keys of the sample structure
  TYPE_KEY                 = 'type'
  TIMESTAMP_KEY            = 'timestamp'
  NAME_KEY                 = 'name'
  DURATION_KEY             = 'duration'

  def initialize( event_listener )
    super()

    @enabled       = false
    @samples       = ::NewRelic::Agent::SampledBuffer.new(NewRelic::Agent.config[MAX_SAMPLES_KEY])
    @notified_full = false

    event_listener.subscribe( :transaction_finished, &method(:on_transaction_finished) )
    self.register_config_callbacks
  end


  ######
  public
  ######

  # Fetch a copy of the sampler's gathered samples. (Synchronized)
  def samples
    return self.synchronize { @samples.to_a }
  end

  def reset!
    NewRelic::Agent.logger.debug "Resetting RequestSampler"

    sample_count, request_count = 0
    old_samples = nil

    self.synchronize do
      sample_count = @samples.size
      request_count = @samples.seen
      old_samples = @samples.to_a
      @samples.reset
      @notified_full = false
    end

    [old_samples, sample_count, request_count]
  end

  # Clear any existing samples, reset the last sample time, and return the
  # previous set of samples. (Synchronized)
  def harvest
    old_samples, sample_count, request_count = reset!
    record_sampling_rate(request_count, sample_count) if @enabled
    old_samples
  end

  # Merge samples back into the buffer, for example after a failed
  # transmission to the collector. (Synchronized)
  def merge!(old_samples)
    self.synchronize do
      old_samples.each { |s| @samples.append(s) }
    end
  end

  def record_sampling_rate(request_count, sample_count)
    request_count_lifetime = @samples.seen_lifetime
    sample_count_lifetime = @samples.captured_lifetime
    NewRelic::Agent.logger.debug("Sampled %d / %d (%.1f %%) requests this cycle, %d / %d (%.1f %%) since startup" % [
      sample_count,
      request_count,
      (sample_count.to_f / request_count * 100.0),
      sample_count_lifetime,
      request_count_lifetime,
      (sample_count_lifetime.to_f / request_count_lifetime * 100.0)
    ])

    engine = NewRelic::Agent.instance.stats_engine
    engine.record_supportability_metric_count("RequestSampler/requests", request_count)
    engine.record_supportability_metric_count("RequestSampler/samples", sample_count)
  end

  def register_config_callbacks
    NewRelic::Agent.config.register_callback(MAX_SAMPLES_KEY) do |max_samples|
      NewRelic::Agent.logger.debug "RequestSampler max_samples set to #{max_samples}"
      self.synchronize { @samples.capacity = max_samples }
      self.reset!
    end

    NewRelic::Agent.config.register_callback(ENABLED_KEY) do |enabled|
      NewRelic::Agent.logger.info "%sabling the Request Sampler." % [ enabled ? 'En' : 'Dis' ]
      @enabled = enabled && NewRelic::Agent.config[ENABLED_TXN_KEY]
    end

    NewRelic::Agent.config.register_callback(ENABLED_TXN_KEY) do |enabled|
      NewRelic::Agent.logger.info "%sabling the Request Sampler." % [ enabled ? 'En' : 'Dis' ]
      @enabled = enabled && NewRelic::Agent.config[ENABLED_KEY]
    end
  end

  def notify_full
    NewRelic::Agent.logger.debug "Request Sampler capacity of #{@samples.capacity} reached, beginning sampling"
    @notified_full = true
  end

  # Event handler for the :transaction_finished event.
  def on_transaction_finished(payload)
    return unless @enabled
    return unless NewRelic::Agent::Transaction.transaction_type_is_web?(payload[:type])
    sample = {
      TIMESTAMP_KEY => float(payload[:start_timestamp]),
      NAME_KEY      => string(payload[:name]),
      DURATION_KEY  => float(payload[:duration]),
      TYPE_KEY      => SAMPLE_TYPE
    }.merge((payload[:overview_metrics] || {}))

    is_full = self.synchronize { @samples.append(sample) }
    notify_full if is_full && !@notified_full
  end
end
