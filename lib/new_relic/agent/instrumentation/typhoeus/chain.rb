# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
require_relative 'typhoeus_tracing'

module NewRelic::Agent::Instrumentation
  module Typhoeus
    module Chain 
      def self.instrument!
        ::Typhoeus::Hydra.class_eval do 
          def run_with_newrelic(*args)
            segment = NewRelic::Agent::Tracer.start_segment(
              name: NewRelic::Agent::Instrumentation::TyphoeusTracing::HYDRA_SEGMENT_NAME
            )
    
            instance_variable_set :@__newrelic_hydra_segment, segment
    
            begin
              run_without_newrelic(*args)
            ensure
              segment.finish if segment
            end
          end
    
          alias run_without_newrelic run
          alias run run_with_newrelic
        end
      end
    end
  end
end