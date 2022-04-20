# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic
  module Agent
    module MethodTracerHelpers
      MAX_ALLOWED_METRIC_DURATION = 1_000_000_000 # roughly 31 years
      SOURCE_CODE_INFORMATION_PARAMETERS = %i[filepath lineno function namespace]
      CODE_INFORMATION_SUCCESS_METRIC = "Supportability/CodeLevelMetrics/Success".freeze
      CODE_INFORMATION_FAILURE_METRIC = "Supportabiltiy/CodeLevelMetrics/Failure".freeze

      extend self

      def trace_execution_scoped(metric_names, options = NewRelic::EMPTY_HASH) # THREAD_LOCAL_ACCESS
        state = NewRelic::Agent::Tracer.state
        return yield unless state.is_execution_traced?

        metric_names = Array(metric_names)
        first_name = metric_names.shift
        return yield unless first_name

        segment = NewRelic::Agent::Tracer.start_segment(
          name: first_name,
          unscoped_metrics: metric_names
        )

        if options[:metric] == false
          segment.record_metrics = false
        end

        unless !options.key?(:code_information) || options[:code_information].nil? || options[:code_information].empty?
          segment.code_information = options[:code_information]
        end

        begin
          Tracer.capture_segment_error(segment) { yield }
        ensure
          segment.finish if segment
        end
      end

      def klass_name(object)
        name = Regexp.last_match(1) if object.to_s =~ /^#<Class:(.*)>$/
        return name if name

        ::NewRelic::Agent.logger.error("Unable to determine a name for '#{object}'")
        nil
      end

      def code_information(object, method_name)
        unless NewRelic::Agent.config[:'code_level_metrics.enabled'] && object && method_name
          return NewRelic::EMTPY_HASH
        end

        @code_information ||= {}
        cache_key = "#{object.object_id}#{method_name}"
        return @code_information[cache_key] if @code_information.key?(cache_key)

        name = object.name if object.respond_to?(:name)
        if name
          location = object.instance_method(method_name).source_location
        else
          name = klass_name(object)
          raise "Unable to glean a class name from string '#{object}'" unless name

          if name.start_with?('0x')
            name = '(Anonymous)'
            location = object.instance_method(method_name).source_location
          else
            location = Object.const_get(name).method(method_name).source_location
          end
        end

        ::NewRelic::Agent.increment_metric(CODE_INFORMATION_SUCCESS_METRIC, 1)

        @code_information[cache_key] = {filepath: location.first,
                                        lineno: location.last,
                                        function: method_name,
                                        namespace: name}
      rescue => e
        ::NewRelic::Agent.logger.error("Unable to determine source code info for '#{object}', " \
                                        "method '#{method_name}' - #{e.class}: #{e.message}")
        ::NewRelic::Agent.increment_metric(CODE_INFORMATION_FAILURE_METRIC, 1)
        ::NewRelic::EMPTY_HASH
      end
    end
  end
end
