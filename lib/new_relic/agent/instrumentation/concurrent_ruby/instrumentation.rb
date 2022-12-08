# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module ConcurrentRuby
    PROMISES_FUTURE_NAME = 'Concurrent::Promises#future'
    POST_NAME = 'Concurrent::ExcutorServce#post'

    def future_with_new_relic(*args)
      segment = NewRelic::Agent::Tracer.start_segment(name: segment_name(*args))
      begin
        NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
      ensure
        ::NewRelic::Agent::Transaction::Segment.finish(segment)
      end
    end

    def post_with_new_relic(*args)
      segment = NewRelic::Agent::Tracer.start_segment(name: POST_NAME)
      begin
        NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
      ensure
        ::NewRelic::Agent::Transaction::Segment.finish(segment)
      end
    end

    private

    def segment_name(*args)
      keyword_args = args[0]
      keyword_args && keyword_args.key?(:nr_name) ? keyword_args[:nr_name] : PROMISES_FUTURE_NAME
    end
  end
end
