# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'newrelic_rpm' unless defined?( NewRelic )
require 'new_relic/agent' unless defined?( NewRelic::Agent )

class NewRelic::Agent::RequestSampler

  # The amount of time between samples, in milliseconds
  DEFAULT_SAMPLE_RATE_MS = 50

  # The number of seconds between harvests
  # :TODO: Get this from the agent instead?
  DEFAULT_REPORT_FREQUENCY = 60

  # The namespace and keys of config values
  CONFIG_NAMESPACE = 'request_sampler'
  SAMPLE_RATE_KEY  = "#{CONFIG_NAMESPACE}.sample_rate_ms".to_sym


  ### Create a new RequestSampler that will keep samples added to it every
  ### +sample_rate+ milliseconds.
  def initialize( event_listener )
    @listener           = event_listener

    @sample_rate        = DEFAULT_SAMPLE_RATE_MS
    @normal_sample_rate = @sample_rate
    @last_sample_taken  = nil
    @last_harvest       = nil
    @samples            = []

    @listener.subscribe( :finished_configuring, &method(:on_finished_configuring) )
  end


  ######
  public
  ######

  # The current sample rate, in milliseconds between samples.
  attr_accessor :sample_rate

  # The samples kept by the sampler
  attr_reader :samples

  # The Time when the last sample was kept
  attr_accessor :last_sample_taken


  ### Clear any existing samples and reset the last sample time.
  def reset
    NewRelic::Agent.logger.debug "Resetting RequestSampler"
    @samples.clear
    @sample_rate = @normal_sample_rate
    @last_sample_taken = Time.at( 0 )
    @last_sample_taken = Time.now
  end


  #
  # Event handlers
  #

  ### Event handler for the :finished_configuring event.
  def on_finished_configuring
    NewRelic::Agent.logger.debug "Finished configuring RequestSampler"

    NewRelic::Agent.config.register_callback(SAMPLE_RATE_KEY) do |rate_ms|
      NewRelic::Agent.logger.debug "  setting RequestSampler sample rate to %dms" % [ rate_ms ]
      @normal_sample_rate = rate_ms
      self.reset
    end

    NewRelic::Agent.logger.debug "  config installed; subscribing to :metrics_recorded events"
    @listener.subscribe( :metrics_recorded, &method(:on_metrics_recorded) )
  end


  ### Event handler for the :before_call event.
  def on_metrics_recorded( metrics, duration, exclusive=false, options={} )
    NewRelic::Agent.logger.debug "On metric recorded: %p (%f)" % [ metrics, duration ]

    # Do nothing unless one of the metrics is a 'Controller/*'
    metric = metrics.find {|metric| metric =~ %r:^Controller/: } or
      return

    self << {
      'type'          => 'Transaction',
      'name'          => metric,
      'response_time' => duration * 1000
    }
  end



  #
  # Sample API
  #

  ### Add a datapoint consisting of a +duration_in_ms+ to the sampler.
  def <<( sample )
    self.add_sample( sample ) if should_sample?
    return self
  end


  ### Add the given +sample+ to the sampler (unconditionally).
  def add_sample( sample )
    NewRelic::Agent.logger.debug "  RequestSampler: adding sample: %p" % [ sample ]
    @samples << sample
    @last_sample_taken = Time.now
  end


  ### Returns +true+ if a sample added now should be kept based on the sample
  ### frequency.
  def should_sample?
    return false unless @last_sample_taken
    return ( Time.now - @last_sample_taken ) * 1000 >= @sample_rate
  end


  # Downsample the gathered data and reduce the sampling rate to conserve memory.
  def downsample_data
    if @last_sample_taken && !@samples.empty?
      NewRelic::Agent.logger.debug "Downsampling RequestSampler"

      resolution = (Time.now - @last_sample_taken) / DEFAULT_REPORT_FREQUENCY
      @sample_rate = @normal_sample_rate * resolution
      NewRelic::Agent.logger.debug "  resolution is now: %d -> 1 sample every %dms" %
        [ resolution, @sample_rate ]

      # I would kill to be able to use >1.9's .select!.with_index, but since it has to
      # work under 1.8.x, too, step up by ones and delete slices of (resolution - 1)
      0.upto( @samples.length / resolution ) {|i| @samples.slice!(i+1, resolution - 1) }
    end
  end

end # class NewRelic::Agent::RequestSampler

