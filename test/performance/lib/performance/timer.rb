# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Performance
  class Timer
    def initialize
      @start_timestamp = nil
      @end_timestamp = nil
    end

    def start(t=Time.now)
      @start_timestamp = t
    end

    def stopped?
      !!@stop_timestamp
    end

    def stop(t=Time.now)
      @stop_timestamp = t
    end

    def measure
      start
      yield
      stop
    end

    def elapsed
      if @stop_timestamp && @start_timestamp
        @stop_timestamp - @start_timestamp
      else
        nil
      end
    end
  end
end
