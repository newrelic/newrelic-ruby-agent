# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
require_relative 'typhoeus_tracing'

module NewRelic::Agent::Instrumentation
  module Typhoeus
    module Prepend
      def run(*args)
        segment = NewRelic::Agent::Tracer.start_segment(
          name: NewRelic::Agent::Instrumentation::TyphoeusTracing::HYDRA_SEGMENT_NAME
        )

        instance_variable_set :@__newrelic_hydra_segment, segment

        begin
          super
        ensure
          segment.finish if segment
        end
      end
    end
  end
end