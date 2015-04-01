module NewRelic
  module Agent
    class Transaction
      class Trace
        attr_reader :start_time, :root_segment

        def initialize(start_time)
          @start_time = start_time
          @root_segment = NewRelic::TransactionSample::Segment.new(0.0, "ROOT")
        end

        def to_collector_array
          [NewRelic::Helper.time_to_millis(self.start_time)]
        end
      end
    end
  end
end
