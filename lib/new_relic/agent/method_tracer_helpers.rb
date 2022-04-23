# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic
  module Agent
    module MethodTracerHelpers
      MAX_ALLOWED_METRIC_DURATION = 1_000_000_000 # roughly 31 years
      SOURCE_CODE_INFORMATION_PARAMETERS = %i[filepath lineno function namespace]
      CODE_INFORMATION_FAILURE_METRIC = "Supportabiltiy/CodeLevelMetrics/Ruby/Failure".freeze

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

      def code_information(object, method_name)
        unless NewRelic::Agent.config[:'code_level_metrics.enabled'] && object && method_name
          return NewRelic::EMTPY_HASH
        end

        @code_information ||= {}
        cache_key = "#{object.object_id}#{method_name}"
        return @code_information[cache_key] if @code_information.key?(cache_key)

        namespace, location = namespace_and_location(object, method_name)

        @code_information[cache_key] = {filepath: location.first,
                                        lineno: location.last,
                                        function: method_name,
                                        namespace: namespace}
      rescue => e
        ::NewRelic::Agent.logger.warn("Unable to determine source code info for '#{object}', " \
                                        "method '#{method_name}' - #{e.class}: #{e.message}")
        ::NewRelic::Agent.increment_metric(CODE_INFORMATION_FAILURE_METRIC, 1)
        ::NewRelic::EMPTY_HASH
      end

      private

      # The string representation of a singleton class looks like
      # '#<Class:MyModule::MyClass>'. Return the 'MyModule::MyClass' part of
      # that string
      def klass_name(object)
        name = Regexp.last_match(1) if object.to_s =~ /^#<Class:(.*)>$/
        return name if name

        raise "Unable to glean a class name from string '#{object}'" unless name
      end

      # determine the namespace (class name and all module names in scope) and
      # source code location (file path and line number) for the given object
      # and a method name
      #
      # traced class methods:
      #     * object is a singleton class, `#<Class::MyClass>`
      #     * object responds to :name, but returns `nil`
      #     * its name must derived from the string representation of the object
      #     * a (non-singleton) class is obtained via a constant lookup
      #
      # traced instance methods and Rails controller methods:
      #     * object is a class, `MyClass`
      #     * object responds to :name and returns its name, `'MyClass'`
      #
      # anonymous class based methods (`c = Class.new { def method; end; }`:
      #    * the string representation of the class has '0x' at the start
      #    * example: `#<Class:0x000000011247f640>`
      #
      def namespace_and_location(object, method_name)
        name = object.name if object.respond_to?(:name)
        return [name, object.instance_method(method_name).source_location] if name

        name = klass_name(object)
        return ['(Anonymous)', location_for_anonymous_class(object, method_name.to_sym)] if name.start_with?('0x')

        # TODO: MLT - let's try object.class, then check #instance_methods on that result
        location = Object.const_get(name).method(method_name).source_location

        [name, location]
      end

      def location_for_anonymous_class(object, method_name)
        if object.instance_methods.include?(method_name)
          object.instance_method(method_name).source_location
        else
          object.method(method_name).source_location
        end
      end
    end
  end
end
