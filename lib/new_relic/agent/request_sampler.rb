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
  DEFAULT_SAMPLE_RATE_MS = 50

  # The number of seconds between harvests
  # :TODO: Get this from the agent instead?
  DEFAULT_REPORT_FREQUENCY = 60

  # The namespace and keys of config values
  CONFIG_NAMESPACE = 'request_sampler'
  SAMPLE_RATE_KEY  = "#{CONFIG_NAMESPACE}.sample_rate_ms".to_sym

  # The type field of the sample
  SAMPLE_TYPE = 'Transaction'

  # Strings for static keys of the sample structure
  TYPE_KEY      = 'type'
  TIMESTAMP_KEY = 'timestamp'
  NAME_KEY      = 'name'
  DURATION_KEY  = 'duration'


  # Create a new RequestSampler that will keep samples added to it every
  # +sample_rate_ms+ milliseconds.
  def initialize( event_listener )
    super()

    @sample_rate_ms_ms     = DEFAULT_SAMPLE_RATE_MS
    @normal_sample_rate_ms = @sample_rate_ms
    @last_sample_taken     = nil
    @last_harvest          = nil
    @samples               = []

    event_listener.subscribe( :finished_configuring, &method(:on_finished_configuring) )
    event_listener.subscribe( :transaction_finished, &method(:on_transaction_finished) )
  end


  ######
  public
  ######

  # The sample rate, in milliseconds between samples, that the sampler uses
  # under normal circumstances
  attr_accessor :normal_sample_rate_ms

  # The current sample rate, which may be different from the #normal_sample_rate_ms
  # if the sampler is throttled.
  attr_accessor :sample_rate_ms

  # The samples kept by the sampler
  attr_reader :samples

  # The Time when the last sample was kept
  attr_accessor :last_sample_taken


  # Clear any existing samples and reset the last sample time. (Synchronized)
  def reset
    NewRelic::Agent.logger.debug "Resetting RequestSampler"

    self.synchronize do
      @samples.clear
      @sample_rate_ms = @normal_sample_rate_ms
      @last_sample_taken = Time.now
    end
  end


  #
  # :group: Event handlers
  #

  # Event handler for the :finished_configuring event.
  def on_finished_configuring
    NewRelic::Agent.logger.debug "Finished configuring RequestSampler"
    NewRelic::Agent.config.register_callback(SAMPLE_RATE_KEY) do |rate_ms|
      NewRelic::Agent.logger.debug "  setting RequestSampler sample rate to %dms" % [ rate_ms ]
      @normal_sample_rate_ms = rate_ms
      self.reset
    end
  end


  # Event handler for the :transaction_finished event.
  def on_transaction_finished( metric, duration, options={} )
    # :TODO: Remove before merging to release branch
    NewRelic::Agent.logger.debug "On metric recorded: %p (%f)" % [ metric, duration ]

    self << {
      NAME_KEY     => string(metric),
      DURATION_KEY => float(duration)
    }
  end



  #
  # :group: Sample API
  # These methods are synchronized.
  #

  # Add a datapoint consisting of a +duration_in_ms+ to the sampler.
  def <<( sample )
    self.synchronize do
      self.add_sample( sample ) if should_sample?
    end

    return self
  end


  # Downsample the gathered data and reduce the sampling rate to conserve memory. The amount
  # the sampler is throttled is proportional to +resolution+, which defaults to the number of
  # normal report periods which have elapsed. E.g., if three sessions with the agent have failed,
  # the sampler downsamples its data to include one out of even three samples, and only samples
  # a third of the time it normally would.
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

  # Returns +true+ if a sample added now should be kept based on the sample
  # frequency.
  def should_sample?
    return false unless @last_sample_taken
    return ( Time.now - @last_sample_taken ) * 1000 >= @sample_rate_ms
  end


  # Add the given +sample+ to the sampler (unconditionally).
  def add_sample( sample )
    @last_sample_taken = Time.now

    sample[TYPE_KEY]      = SAMPLE_TYPE
    sample[TIMESTAMP_KEY] = @last_sample_taken

    @samples << sample
  end


  # Downsample the current data to match the specified +resolution+.
  def downsample_data( resolution )
    goalsize = @samples.length * ( (resolution - 1) / resolution.to_f )
    0.step( goalsize, resolution - 1 ) {|i| @samples.slice!(i+1) }
  end

end # class NewRelic::Agent::RequestSampler

