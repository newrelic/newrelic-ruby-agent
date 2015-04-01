module NewRelic
  module Agent
    class Transaction
      class Trace
        attr_reader :start_time

        def initialize(start_time)
          @start_time = start_time
        end

        def to_collector_array
          [NewRelic::Helper.time_to_millis(self.start_time)]
        end
      end
    end
  end
end
