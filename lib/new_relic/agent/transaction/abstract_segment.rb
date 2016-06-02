# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class Transaction
      class AbstractSegment
        attr_reader :start_time, :end_time, :duration, :exclusive_duration
        attr_accessor :name, :children_time, :transaction

        def initialize name
          @name = name
          @children_time = 0.0
          @record_metrics = true
          @transaction = nil
        end

        def start
          @start_time = Time.now
        end

        def finish
          @end_time = Time.now
          @duration = @end_time.to_f - @start_time.to_f
          @exclusive_duration = @duration - children_time
        end
      end
    end
  end
end
