# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module MethodTracerHelpers
      MAX_ALLOWED_METRIC_DURATION = 1_000_000_000 # roughly 31 years

      extend self

      def trace_execution_scoped(metric_names, options={}) #THREAD_LOCAL_ACCESS
        state = NewRelic::Agent::TransactionState.tl_get
        return yield unless state.is_execution_traced?

        metric_names = Array(metric_names)
        first_name   = metric_names.shift
        return yield unless first_name

        segment = NewRelic::Agent::Transaction.start_segment(
          name: first_name,
          unscoped_metrics: metric_names
        )

        if options[:metric] == false
          segment.record_metrics = false
        end

        begin
          yield
        ensure
          segment.finish if segment
        end
      end
    end
  end
end
