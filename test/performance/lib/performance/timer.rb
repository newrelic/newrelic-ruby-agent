# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Performance
  class Timer
    attr_accessor :start_timestamp, :stop_timestamp, :elapsed

    def initialize
      @start_timestamp = nil
      @stop_timestamp = nil
      @elapsed = 0.0
      @most_recent_start = nil
    end

    def start(t=Time.now)
      @start_timestamp ||= t
      @most_recent_start = t
    end

    def stopped?
      !!@stop_timestamp
    end

    def stop(t=Time.now)
      @stop_timestamp = t
      @elapsed += t - @most_recent_start
    end

    def measure
      start
      yield
      stop
    end

    def inspect
      "<Performance::Timer @start_timestamp=#{start_timestamp.inspect}, @stop_timestamp=#{stop_timestamp.inspect}, elapsed=#{elapsed}>"
    end
  end
end
