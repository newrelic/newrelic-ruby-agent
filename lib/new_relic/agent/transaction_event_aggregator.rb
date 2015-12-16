# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'newrelic_rpm' unless defined?( NewRelic )
require 'new_relic/agent' unless defined?( NewRelic::Agent )
require 'new_relic/agent/event_aggregator'

class NewRelic::Agent::TransactionEventAggregator < NewRelic::Agent::EventAggregator

  named :TransactionEventAggregator
  capacity_key :'analytics_events.max_samples_stored'
  enabled_key :'analytics_events.enabled'

  # Fetch a copy of the sampler's gathered samples. (Synchronized)
  def samples
    return @lock.synchronize { @buffer.to_a }
  end

  def append(event)
    return unless @enabled

    @lock.synchronize do
      @buffer.append event.to_collector_array
      notify_if_full
    end
  end

  private

  def after_harvest metadata
    return unless enabled?
    record_sampling_rate metadata
  end

  def record_sampling_rate(metadata) #THREAD_LOCAL_ACCESS

    NewRelic::Agent.logger.debug("Sampled %d / %d (%.1f %%) requests this cycle, %d / %d (%.1f %%) since startup" % [
      metadata[:captured],
      metadata[:seen],
      (metadata[:captured].to_f / metadata[:seen] * 100.0),
      metadata[:captured_lifetime],
      metadata[:seen_lifetime],
      (metadata[:captured_lifetime].to_f / metadata[:seen_lifetime] * 100.0)
    ])

    engine = NewRelic::Agent.instance.stats_engine
    engine.tl_record_supportability_metric_count("TransactionEventAggregator/requests", metadata[:seen])
    engine.tl_record_supportability_metric_count("TransactionEventAggregator/samples", metadata[:captured])
  end
end
