# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/segment'

module NewRelic
  module Agent
    class Transaction
      module Tracing
        def start_segment name, unscoped_metrics=nil
          segment = create_segment name, unscoped_metrics
          segment.start
          segment
        end

        def create_segment name, unscoped_metrics
          segment = Segment.new name, unscoped_metrics
          segment
        end
      end
    end
  end
end
