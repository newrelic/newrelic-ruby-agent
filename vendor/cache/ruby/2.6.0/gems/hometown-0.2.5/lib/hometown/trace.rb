module Hometown
  class Trace
    attr_reader :traced_class, :backtrace

    def initialize(traced_class, backtrace)
      @traced_class = traced_class
      @backtrace    = backtrace
    end

    def eql?(b)
      @traced_class == b.traced_class &&
        @backtrace  == b.backtrace
    end

    def hash
      [@traced_class, @backtrace].hash
    end
  end
end
