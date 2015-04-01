# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class Transaction
      class Trace
        attr_reader :start_time, :root_segment
        attr_accessor :transaction_name, :uri

        def initialize(start_time)
          @start_time = start_time
          @root_segment = NewRelic::TransactionSample::Segment.new(0.0, "ROOT")
        end

        def to_collector_array
          [
            NewRelic::Helper.time_to_millis(self.start_time),
            NewRelic::Helper.time_to_millis(self.root_segment.duration),
            NewRelic::Coerce.string(self.transaction_name),
            NewRelic::Coerce.string(self.uri)
          ]
        end
      end
    end
  end
end
