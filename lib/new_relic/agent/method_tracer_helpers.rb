# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic
  module Agent
    module MethodTracerHelpers
      MAX_ALLOWED_METRIC_DURATION = 1_000_000_000 # roughly 31 years
      SOURCE_CODE_INFORMATION_PARAMETERS = %i[filepath lineno function namespace]

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

      def class_info(object)
        name = object.name

        return [name, true] if name
        return [Regexp.last_match(1), false] if object.to_s =~ /^#<Class:(.*)>$/

        ::NewRelic::Agent.logger.error("Unable to determine name for what was expected to be a singleton class, #{object}")
        [nil, nil]
      end

      def class_or_instance(name, is_instance_method)
        klass = Object.const_get(name)
        return klass unless is_instance_method

        klass.new
      end

      def location(name, method_name, is_instance_method)
        begin
          class_or_instance(name, is_instance_method).method(method_name).source_location
        rescue => e
          ::NewRelic::Agent.logger.error("Unable to determine source code info for class '#{name}', " \
                                          "method '#{method_name}' - #{e.class}: #{e.message}")
          []
        end
      end

      def code_information(object, method_name)
        return NewRelic::EMTPY_HASH unless NewRelic::Agent.config[:'code_level_metrics.enabled']

        klass_name, is_instance_method = class_info(object)
        return NewRelic::EMPTY_HASH unless klass_name

        file_info = location(klass_name, method_name, is_instance_method)
        namespace = Regexp.last_match(1) if klass_name =~ /(.*)::[^:]+/

        {filepath: file_info.first,
         lineno: file_info.last,
         function: method_name,
         namespace: namespace}
      end
    end
  end
end
