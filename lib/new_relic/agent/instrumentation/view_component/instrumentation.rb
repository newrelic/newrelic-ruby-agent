# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module ViewComponent
    INSTRUMENTATION_NAME = NewRelic::Agent.base_name(name)

    def render_in_with_tracing(*args)
      NewRelic::Agent.record_instrumentation_invocation(INSTRUMENTATION_NAME)

      begin
        segment = NewRelic::Agent::Tracer.start_segment(
          name: metric_name(self.class.identifier, self.class.name)
        )
        yield
      rescue => e
        NewRelic::Agent.notice_error(e)
        raise
      ensure
        segment&.finish
      end
    end

    def metric_name(identifier, component)
      "View/#{metric_path(identifier)}/#{component}"
    end

    def metric_path(identifier)
      return 'component' unless identifier

      if (parts = identifier.split('/')).size > 1
        parts[-2..-1].join('/') # Get filepath by assuming the Rails' structure: app/components/home/example_component.rb
      else
        NewRelic::Agent::UNKNOWN_METRIC
      end
    end
  end
end
