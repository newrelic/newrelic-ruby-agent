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

  # The amount of time between samples, in milliseconds
  DEFAULT_SAMPLE_RATE_MS   = 50

  # The minimum amount of time between samples, in milliseconds
  MIN_SAMPLE_RATE_MS       = 25

  # The number of seconds between harvests
  # :TODO: Get this from the agent instead?
  DEFAULT_REPORT_FREQUENCY = 60

  # Regardless of whether #throttle is successfully called, we will store
  # at most this many harvest-cycles worth of samples total, to avoid unbounded
  # memory growth when there's a low-level failure talking to the collector.
  MAX_FAILED_REPORT_RETENTION = 10

  # The namespace and keys of config values
  CONFIG_NAMESPACE = 'request_sampler'
  SAMPLE_RATE_KEY  = "#{CONFIG_NAMESPACE}.sample_rate_ms".to_sym
  ENABLED_KEY      = "#{CONFIG_NAMESPACE}.enabled".to_sym

  # The type field of the sample
  SAMPLE_TYPE              = 'Transaction'

  # Strings for static keys of the sample structure
  TYPE_KEY                 = 'type'
  TIMESTAMP_KEY            = 'timestamp'
  NAME_KEY                 = 'name'
  DURATION_KEY             = 'duration'


  # Create a new RequestSampler that will keep samples added to it every
  # +sample_rate_ms+ milliseconds.
  def initialize( event_listener )
    super()

    @enabled               = false
    @sample_rate_ms        = DEFAULT_SAMPLE_RATE_MS
    @normal_sample_rate_ms = @sample_rate_ms
    @last_sample_taken     = nil
    @samples               = []
    @notified_max_samples  = false

    @sample_count          = 0
    @request_count         = 0
    @sample_count_total    = 0
    @request_count_total   = 0

    event_listener.subscribe( :transaction_finished, &method(:on_transaction_finished) )
    self.register_config_callbacks
  end


  ######
  public
  ######

  # The sample rate, in milliseconds between samples, that the sampler uses
  # under normal circumstances
  attr_reader :normal_sample_rate_ms

  # The current sample rate, which may be different from the #normal_sample_rate_ms
  # if the sampler is throttled.
  attr_reader :sample_rate_ms

  # The Time when the last sample was kept
  attr_reader :last_sample_taken


  ### Fetch a copy of the sampler's gathered samples. (Synchronized)
  def samples
    return self.synchronize { @samples.dup }
  end


  # Clear any existing samples and reset the last sample time. (Synchronized)
  def reset
    NewRelic::Agent.logger.debug "Resetting RequestSampler"

    request_count = nil
    sample_count = nil

    self.synchronize do
      sample_count = @samples.size
      request_count = @request_count
      @request_count = 0
      @samples.clear
      @sample_rate_ms = @normal_sample_rate_ms
      @last_sample_taken = Time.now
      @notified_max_samples = false
    end

    record_sampling_rate(request_count, sample_count) if @enabled
  end

  def record_sampling_rate(request_count, sample_count)
    @request_count_total += request_count
    @sample_count_total  += sample_count

    NewRelic::Agent.logger.debug("Sampled #{sample_count} / #{request_count} (%.1f %%) requests this cycle" % (sample_count.to_f / request_count * 100.0))
    NewRelic::Agent.logger.debug("Sampled #{@sample_count_total} / #{@request_count_total} (%.1f %%) requests since startup" % (@sample_count_total.to_f / @request_count_total * 100.0))

    engine = NewRelic::Agent.instance.stats_engine
    engine.record_supportability_metric_count("RequestSampler/requests", request_count)
    engine.record_supportability_metric_count("RequestSampler/samples", sample_count)
  end

  #
  # :group: Event handlers
  #

  def register_config_callbacks
    NewRelic::Agent.config.register_callback(SAMPLE_RATE_KEY) do |rate_ms|
      NewRelic::Agent.logger.debug "RequestSampler sample rate to %dms" % [ rate_ms ]

      if rate_ms < MIN_SAMPLE_RATE_MS
        NewRelic::Agent.logger.warn "  limiting RequestSampler frequency to %dms (was %dms)" %
          [ MIN_SAMPLE_RATE_MS, rate_ms ]
        rate_ms = MIN_SAMPLE_RATE_MS
      end

      @normal_sample_rate_ms = rate_ms
      @max_samples = calculate_max_samples
      NewRelic::Agent.logger.debug "RequestSampler max_samples set to #{@max_samples}"
      self.reset
    end

    NewRelic::Agent.config.register_callback(ENABLED_KEY) do |enabled|
      NewRelic::Agent.logger.info "%sabling the Request Sampler." % [ enabled ? 'En' : 'Dis' ]
      @enabled = enabled
    end
  end


  # Event handler for the :transaction_finished event.
  def on_transaction_finished( metric, start_timestamp, duration, options={} )
    return unless @enabled
    self << {
      TIMESTAMP_KEY => float(start_timestamp),
      NAME_KEY      => string(metric),
      DURATION_KEY  => float(duration)
    }.merge(options)
  end



  #
  # :group: Sample API
  # These methods are synchronized.
  #

  # Add a datapoint to the sampler if a sample is due. The +sample+ should be
  # of the form:
  #
  #   {
  #     'name' => '<transaction/metric name>',
  #     'duration' => <duration in seconds as a Float>,
  #   }
  #
  # This method is synchronized.
  def <<( sample )
    self.synchronize do
      @request_count += 1
      self.add_sample( sample ) if should_sample?
    end

    return self
  end


  # Downsample the gathered data and reduce the sampling rate to conserve memory. The amount
  # the sampler is throttled is proportional to +resolution+, which defaults to the number of
  # normal report periods which have elapsed. E.g., if three sessions with the agent have failed,
  # the sampler downsamples its data to include one out of even three samples, and only samples
  # a third of the time it normally would.
  #
  # This method is synchronized.
  def throttle( resolution=nil )

    # Only throttle if the sampler was running
    self.synchronize do
      if @last_sample_taken && !@samples.empty?
        resolution ||= (Time.now - @last_sample_taken) / DEFAULT_REPORT_FREQUENCY
        @sample_rate_ms = @normal_sample_rate_ms * resolution
        self.downsample_data( resolution )
      end
    end

    if resolution
      NewRelic::Agent.logger.debug "  resolution is now: %d -> 1 sample every %dms" %
        [ resolution, @sample_rate_ms ]
    end
  end


  #########
  protected
  #########

  def calculate_max_samples
    max_samples_per_harvest = (DEFAULT_REPORT_FREQUENCY * 1000.0) / @normal_sample_rate_ms
    max_samples_per_harvest * MAX_FAILED_REPORT_RETENTION
  end

  # Returns +true+ if a sample added now should be kept based on the sample
  # frequency.
  def should_sample?
    return false unless @last_sample_taken
    if @samples.size >= @max_samples
      unless @notified_max_samples
        NewRelic::Agent.logger.warn("Reached maximum of #{@max_samples} samples, ceasing collection")
        @notified_max_samples = true
      end
      return false
    end
    return ((Time.now - @last_sample_taken) * 1000).ceil >= @sample_rate_ms
  end


  # Add the given +sample+ to the sampler (unconditionally).
  def add_sample( sample )
    @last_sample_taken = Time.now

    sample[TYPE_KEY]      = SAMPLE_TYPE
    @samples << sample
  end


  # Downsample the current data to match the specified +resolution+.
  def downsample_data( resolution )
    goalsize = @samples.length * ( (resolution - 1) / resolution.to_f )
    0.step( goalsize.ceil, resolution - 1 ) {|i| @samples.slice!(i+1) }
  end

end # class NewRelic::Agent::RequestSampler
