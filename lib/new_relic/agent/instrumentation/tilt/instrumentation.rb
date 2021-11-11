# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic
  module Agent
    module Instrumentation
      module Tilt
        # Template name, etc. isn't available until Render. Those things are set in initialize.
        # I'm uncertain about whether
        def initialize_with_tracing(*args, &block)
          begin
            finishable = Tracer.start_segment(name: "#{self.class}#initialize")
            yield
            finishable.finish
          rescue StandardError => error
            binding.pry
            NewRelic::Agent.logger.error(
              "Error while executing Tilt::Template#initialize",
              error
            )
            NewRelic::Agent.logger.log_exception(:error, error)
          end
        end
      end
    end
  end
end
