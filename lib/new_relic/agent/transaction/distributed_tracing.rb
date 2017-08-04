module NewRelic
  module Agent
    class Transaction
      module DistributedTracing

        def distributed_tracing_trip_id
          guid
        end

        def depth
          1
        end

        def order
          0
        end
      end
    end
  end
end
