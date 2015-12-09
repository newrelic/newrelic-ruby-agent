# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'monitor'

require 'newrelic_rpm' unless defined?( NewRelic )
require 'new_relic/agent' unless defined?( NewRelic::Agent )

class NewRelic::Agent::TransactionEventAggregator
  include MonitorMixin

  def initialize
    super

    @enabled       = false
    @notified_full = false
    @samples       = ::NewRelic::Agent::SampledBuffer.new(NewRelic::Agent.config[:'analytics_events.max_samples_stored'])

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
    sample_count, request_count = 0, 0
    old_samples = nil

    self.synchronize do
      sample_count = @samples.size
      request_count = @samples.num_seen

      old_samples = @samples.to_a
      @samples.reset!

      @notified_full = false
    end

    [old_samples, sample_count, request_count]
  end

  # Clear any existing samples, reset the last sample time, and return the
  # previous set of samples. (Synchronized)
  def harvest!
    old_samples, sample_count, request_count = reset!
    record_sampling_rate(request_count, sample_count) if @enabled
    old_samples
  end

  # Merge samples back into the buffer, for example after a failed
  # transmission to the collector. (Synchronized)
  def merge!(old_samples)
    self.synchronize do
      old_samples.each { |s| @samples.append s }
    end
  end

  def record_sampling_rate(request_count, sample_count) #THREAD_LOCAL_ACCESS
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
    engine.tl_record_supportability_metric_count("TransactionEventAggregator/requests", request_count)
    engine.tl_record_supportability_metric_count("TransactionEventAggregator/samples", sample_count)
  end

  def register_config_callbacks
    NewRelic::Agent.config.register_callback(:'analytics_events.max_samples_stored') do |max_samples|
      NewRelic::Agent.logger.debug "TransactionEventAggregator max_samples set to #{max_samples}"
      self.synchronize { @samples.capacity = max_samples }
    end

    NewRelic::Agent.config.register_callback(:'analytics_events.enabled') do |enabled|
      @enabled = enabled
    end
  end

  def notify_full
    NewRelic::Agent.logger.debug "Transaction event capacity of #{@samples.capacity} reached, beginning sampling"
    @notified_full = true
  end

  def append(event)
    return unless @enabled

    self.synchronize { @samples.append event.to_collector_array }
    notify_full if !@notified_full && @samples.full?
  end

  # def append_event(event)
  #   # main_event, _ = event

  #   # if main_event.include?(TransactionEvent::SYNTHETICS_RESOURCE_ID_KEY)
  #   #   # Try adding to synthetics buffer. If anything is rejected, give it a
  #   #   # shot in the main transaction events (where it may get sampled)
  #   #   _, rejected = @synthetics_samples.append_with_reject(event)

  #   #   if rejected
  #   #     @samples.append(rejected)
  #   #   end
  #   # else
  #     @samples.append(event)
  #   # end
  # end
end
