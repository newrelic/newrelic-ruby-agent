# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'newrelic_rpm' unless defined?( NewRelic )
require 'new_relic/agent' unless defined?( NewRelic::Agent )

class NewRelic::Agent::RequestSampler

  # The amount of time between samples, in milliseconds
  DEFAULT_SAMPLE_RATE_MS = 50

  # The period of time between reports, in seconds.
  DEFAULT_REPORT_FREQUENCY = 60


  ### Create a new RequestSampler that will keep samples added to it every
  ### +sample_rate+ milliseconds.
  def initialize( sample_rate=DEFAULT_SAMPLE_RATE_MS, report_frequency=DEFAULT_REPORT_FREQUENCY )
    @sample_rate        = sample_rate
    @normal_sample_rate = sample_rate
    @report_frequency   = report_frequency
    @last_sample_taken  = Time.at( 0 )
    @last_harvest       = Time.now
    @samples            = []
    @thread             = nil
  end


  ######
  public
  ######

  # The current sample rate, in milliseconds between samples.
  attr_accessor :sample_rate

  # The number of seconds between posting reports
  attr_accessor :report_frequency

  # The samples kept by the sampler
  attr_reader :samples

  # The Time when the last sample was kept
  attr_accessor :last_sample_taken


  ### Add a datapoint consisting of a +duration_in_ms+ to the sampler.
  def <<( duration_in_ms )
    self.add_sample( duration_in_ms ) if should_sample?
  end


  ### Add the given +sample+ to the sampler (unconditionally).
  def add_sample( sample )
    @samples << sample
    @last_sample_taken = Time.now
  end


  ### Returns +true+ if a sample added now should be kept based on the sample
  ### frequency.
  def should_sample?
    ( Time.now - @last_sample_taken ) * 1000 >= @sample_rate
  end


  ### Clear any existing samples and reset the last sample time.
  def reset
    @samples.clear
    @sample_rate = @normal_sample_rate
    @last_sample_taken = Time.at( 0 )
    @last_sample_taken = Time.now
  end


  # Downsample the gathered data and reduce the sampling rate to conserve memory.
  def downsample_data
    resolution = (Time.now - @last_sample_taken) / DEFAULT_REPORT_FREQUENCY
    @sample_rate = @normal_sample_rate * resolution

    # I would kill to be able to use >1.9's .select!.with_index, but since it has to
    # work under 1.8.x, too, step up by ones and delete slices of (resolution - 1)
    0.upto( @samples.length / resolution ) {|i| @samples.slice!(i+1, resolution - 1) }
  end

end # class NewRelic::Agent::RequestSampler

