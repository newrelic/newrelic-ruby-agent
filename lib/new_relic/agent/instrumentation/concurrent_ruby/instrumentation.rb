# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module ConcurrentRuby
    DEFAULT_NAME = 'Concurrent::ThreadPoolExecutor#post'

    def post_with_new_relic(*args)
      return yield unless NewRelic::Agent::Tracer.tracing_enabled?

      segment = NewRelic::Agent::Tracer.start_segment(name: DEFAULT_NAME)
      begin
        NewRelic::Agent::Tracer.capture_segment_error(segment) do
          yield
        end
      ensure
        ::NewRelic::Agent::Transaction::Segment.finish(segment)
      end
    end
  end
end
