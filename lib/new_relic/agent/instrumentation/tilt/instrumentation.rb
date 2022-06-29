# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Instrumentation
      module Tilt
        def metric_name(klass, file)
          "View/#{klass}/#{file}/Rendering"
        end

        # Sinatra uses #caller_locations for the file name in Tilt (unlike Rails/Rack)
        # So here we are only grabbing the file name and name of directory it is in
        def create_filename_for_metric(file)
          return file unless defined?(::Sinatra) && defined?(::Sinatra::Base)
          file.split('/')[-2..-1].join('/')
        rescue NoMethodError
          file
        end

        def render_with_tracing(*args, &block)
          begin
            finishable = Tracer.start_segment(
              name: metric_name(self.class, create_filename_for_metric(self.file))
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
