# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic
  module Agent
    module Instrumentation
      module Tilt

        def metric_name(klass, file)
          "View/#{klass}/#{file}/Rendering"
        end

        def render_with_tracing(*args, &block)
          begin
            finishable = Tracer.start_segment(
              name: metric_name(self.class, self.file)
            )
            begin
              yield
            rescue => error
              NewRelic::Agent.notice_error(error)
              raise
            end
          ensure
            finishable.finish if finishable
          end
        end
      end
    end
  end
end
