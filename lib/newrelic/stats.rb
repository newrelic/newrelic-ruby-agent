require 'newrelic/metric_data'

module NewRelic
  module Stats
    def average_call_time
      return 0 if call_count == 0
      total_call_time / call_count
    end
    
    def average_exclusive_time
      return 0 if call_count == 0
      total_exclusive_time / call_count
    end
    
    def merge! (other_stats)
      Array(other_stats).each do |s|
        self.total_call_time += s.total_call_time
        self.total_exclusive_time += s.total_exclusive_time
        self.min_call_time = s.min_call_time if s.min_call_time < min_call_time || call_count == 0
        self.max_call_time = s.max_call_time if s.max_call_time > max_call_time
        self.call_count += s.call_count
        # FIXME THIS IS BROKEN!  How do we merge variances?
        self.variance += s.variance
        self.begin_time = s.begin_time if s.begin_time < begin_time || begin_time.to_f == 0.0
        self.end_time = s.end_time if s.end_time > end_time
      end
      
      self
    end
    
    def merge (other_stats)
      stats = self.clone
      stats.merge! other_stats
    end
    
    # split into an array of timesclices whose
    # time boundaries start on (begin_time + (n * duration)) and whose
    # end time ends on (begin_time * (n + 1) * duration), except for the
    # first and last elements, whose begin time and end time are the begin
    # and end times of this stats instance, respectively.  Yield to caller
    # for the code that creates the actual stats instance
    def split(rollup_begin_time, rollup_period)
      rollup_begin_time = rollup_begin_time.to_f
      rollup_begin_time += ((self.begin_time - rollup_begin_time) / rollup_period).floor * rollup_period

      current_begin_time = self.begin_time
      current_end_time = rollup_begin_time + rollup_period

      return [self] if current_end_time >= self.end_time
      
      timeslices = []
      while current_end_time < self.end_time do
        ts = yield(current_begin_time, current_end_time)
        
        ts.fraction_of(self)
        timeslices << ts
        current_begin_time = current_end_time
        current_end_time = current_begin_time + rollup_period
      end
      
      if self.end_time > current_begin_time
        percentage = rollup_period / self.duration + (self.begin_time - rollup_begin_time) / rollup_period
        ts = yield(current_begin_time, self.end_time)
        ts.fraction_of(self)
        timeslices << ts
      end
      
      timeslices
    end
    
    def reset
      self.call_count = 0
      self.total_call_time = 0.0
      self.total_exclusive_time = 0.0
      self.min_call_time = 0.0
      self.max_call_time = 0.0
      self.variance = 0.0
      self.begin_time = Time.at(0)
      self.end_time = Time.at(0)
    end
    
    def as_percentage_of(other_stats)
      return 0 if other_stats.total_call_time == 0
      return (total_call_time / other_stats.total_call_time).to_percentage
    end
    
    def duration
      end_time - begin_time
    end

    def calls_per_minute
      return 0 if duration.zero?
      ((call_count / duration.to_f * 6000).round).to_f / 100
    end
    
    def standard_deviation
      return 0 if call_count < 2
      Math.sqrt(variance / (call_count - 1))
    end
    
    # returns the time spent in this component as a percentage of the total
    # time window.
    def time_percentage
      return 0 if duration == 0
      total_call_time / duration
    end

    def exclusive_time_percentage
      return 0 if duration == 0
      total_exclusive_time / duration
    end

    alias average_value average_call_time
    
    def to_s
      s = "Begin=#{begin_time}, "
      s << "Duration=#{duration} s, "
      s << "Count=#{call_count}, "
      s << "Total=#{total_call_time.to_ms}, "
      s << "Total Exclusive=#{total_exclusive_time.to_ms}, "
      s << "Avg=#{average_call_time.to_ms}, "
      s << "Min=#{min_call_time.to_ms}, "
      s << "Max=#{max_call_time.to_ms}"
    end

    # calculate this set of stats to be a percentage fraction 
    # of the provided stats, which has an overlapping time window.
    # used as a key part of the split algorithm
    def fraction_of(s)
      min_end = (end_time < s.end_time ? end_time : s.end_time)
      max_begin = (begin_time > s.begin_time ? begin_time : s.begin_time)
      percentage = (min_end - max_begin) / s.duration
      
      self.total_call_time = s.total_call_time * percentage
      self.min_call_time = s.min_call_time
      self.max_call_time = s.max_call_time
      self.call_count = s.call_count * percentage
      self.variance = s.variance * percentage
    end
    
    # multiply the total time and rate by the given percentage 
    def multiply_by(percentage)
      self.total_call_time = total_call_time * percentage
      self.call_count = call_count * percentage
      self.variance = variance * percentage
      
      self
    end
  end
  
  # Statistics used to track the performance of traced methods
  class MethodTraceStats
    include Stats
    
    attr_accessor :call_count
    attr_accessor :min_call_time
    attr_accessor :max_call_time
    attr_accessor :total_call_time
    attr_accessor :total_exclusive_time
    attr_accessor :variance
    
    alias data_point_count call_count
    
    def initialize 
      reset
    end
    
    # This is the source code I found on a google search for standard deviation calculation.
    # I need to convert the algorithm to accumulate on the fly rather than process
    # the entire set.
    # def variance(population)
    #   n = 0
    #   mean = 0.0
    #   s = 0.0
    #   population.each { |x|
    #     n = n + 1
    #     delta = x - mean
    #     mean = mean + (delta / n)
    #     s = s + delta * (x - mean)
    #   }
    #   # if you want to calculate std deviation
    #   # of a sample change this to "s / (n-1)"
    #   return s / n
    # end
    # 
    # # calculate the standard deviation of a population
    # # accepts: an array, the population
    # # returns: the standard deviation
    # def standard_deviation(population)
    #   Math.sqrt(variance(population))
    # end
        
    # record a single data point into the statistical gatherer.  The gatherer
    # will aggregate all data points collected over a specified period and upload
    # its data to the NewRelic server
    def record_data_point(value, exclusive_time = nil)
      exclusive_time ||= value
      
      # update the variance accumulator for calculating the standard deviation
      delta = value - average_value
      
      @call_count += 1
      @total_call_time += value
      @min_call_time = value if value < @min_call_time || @call_count == 1
      @max_call_time = value if value > @max_call_time
      @total_exclusive_time += exclusive_time

      @variance += delta * (value - average_value)
      
      self
    end

    alias :trace_call :record_data_point

    def freeze
      @end_time = Time.now
      super
    end
    
    # In this class, we explicitly don't track begin and end time here, to save space during
    # cross process serialization via xml.  Still the accessor methods must be provided for merge to work.
    def begin_time=(t)
    end
    
    def end_time=(t)
    end
    
    def begin_time
      0.0
    end
    
    def end_time
      0.0
    end
  end
  
  class ScopedMethodTraceStats < MethodTraceStats
    def initialize(unscoped_stats)
      super()
      
      @unscoped_stats = unscoped_stats
    end
    
    def trace_call(call_time, exclusive_time = nil)
      @unscoped_stats.trace_call call_time, exclusive_time
      super call_time, exclusive_time
    end
  end
end

class Numeric
  # utlity method that converts floating point time values in seconds
  # to integers in milliseconds, to improve readability in ui
  def to_ms(decimal_places = 0)
    (self * 1000).round_to(decimal_places)
  end
  
  def to_ns(decimal_places = 0)
    (self * 1000000).round_to(decimal_places)
  end
  
  # utility method that converts floating point percentage values
  # to integers as a percentage, to improve readability in ui
  def to_percentage(decimal_places = 2)
    (self * 100).round_to(decimal_places)
  end
  
  def round_to(decimal_places)
    x = self
    decimal_places.times do
      x = x * 10
    end
    x = x.round
    decimal_places.times do
      x = x.to_f / 10
    end
    x
  end
  
  def round_to_1
    round_to(1)
  end

  def round_to_2
    round_to(2)
  end

  def round_to_3
    round_to(3)
  end
end