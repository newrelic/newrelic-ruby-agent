# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

# This file may be independently required to set up method tracing prior to
# the full agent loading. In those cases, we do need at least this require to
# bootstrap things.
require 'new_relic/control' unless defined?(NewRelic::Control)

require 'new_relic/agent/method_tracer_helpers'

module NewRelic
  module Agent
    # This module contains class methods added to support installing custom
    # metric tracers and executing for individual metrics.
    #
    # == Examples
    #
    # When the agent initializes, it extends Module with these methods.
    # However if you want to use the API in code that might get loaded
    # before the agent is initialized you will need to require
    # this file:
    #
    #     require 'new_relic/agent/method_tracer'
    #     class A
    #       include NewRelic::Agent::MethodTracer
    #       def process
    #         ...
    #       end
    #       add_method_tracer :process
    #     end
    #
    # To instrument a class method:
    #
    #     require 'new_relic/agent/method_tracer'
    #     class An
    #       def self.process
    #         ...
    #       end
    #       class << self
    #         include NewRelic::Agent::MethodTracer
    #         add_method_tracer :process
    #       end
    #     end
    #
    # @api public
    #

    module MethodTracer

      def self.included(klass)
        klass.extend(ClassMethods)
        klass.prepend(_nr_traced_method_module)
      end

      def self.extended(klass)
        klass.extend(ClassMethods)
        klass.prepend(_nr_traced_method_module)
      end

      # Trace a given block with stats and keep track of the caller.
      # See NewRelic::Agent::MethodTracer::ClassMethods#add_method_tracer for a description of the arguments.
      # +metric_names+ is either a single name or an array of metric names.
      # If more than one metric is passed, the +produce_metric+ option only applies to the first.  The
      # others are always recorded.  Only the first metric is pushed onto the scope stack.
      #
      # Generally you pass an array of metric names if you want to record the metric under additional
      # categories, but generally this *should never ever be done*.  Most of the time you can aggregate
      # on the server.
      #
      # @api public
      #
      def trace_execution_scoped(metric_names, options=NewRelic::EMPTY_HASH) #THREAD_LOCAL_ACCESS
        NewRelic::Agent.record_api_supportability_metric :trace_execution_scoped
        NewRelic::Agent::MethodTracerHelpers.trace_execution_scoped(metric_names, options) do
          # Using an implicit block avoids object allocation for a &block param
          yield
        end
      end

      # Trace a given block with stats assigned to the given metric_name.  It does not
      # provide scoped measurements, meaning whatever is being traced will not 'blame the
      # Controller'--that is to say appear in the breakdown chart.
      # This is code is inlined in #add_method_tracer.
      # * <tt>metric_names</tt> is a single name or an array of names of metrics
      #
      # @api public
      #
      def trace_execution_unscoped(metric_names, options=NewRelic::EMPTY_HASH) #THREAD_LOCAL_ACCESS
        NewRelic::Agent.record_api_supportability_metric :trace_execution_unscoped
        return yield unless NewRelic::Agent.tl_is_execution_traced?
        t0 = Time.now
        begin
          yield
        ensure
          duration = (Time.now - t0).to_f              # for some reason this is 3 usec faster than Time - Time
          NewRelic::Agent.instance.stats_engine.tl_record_unscoped_metrics(metric_names, duration)
        end
      end

      # Defines methods used at the class level, for adding instrumentation
      # @api public
      module ClassMethods
        # contains methods refactored out of the #add_method_tracer method
        module AddMethodTracer
          ALLOWED_KEYS = [:metric, :push_scope, :code_header, :code_footer].freeze

          DEFAULT_SETTINGS = {:push_scope => true, :metric => true, :code_header => "", :code_footer => "" }.freeze

          # Checks the provided options to make sure that they make
          # sense. Raises an error if the options are incorrect to
          # assist with debugging, so that errors occur at class
          # construction time rather than instrumentation run time
          def _nr_validate_method_tracer_options(method_name, options)
            unless options.is_a?(Hash)
              raise TypeError.new("Error adding method tracer to #{method_name}: provided options must be a Hash")
            end

            unrecognized_keys = options.keys - ALLOWED_KEYS
            if unrecognized_keys.any?
              raise "Unrecognized options when adding method tracer to #{method_name}: " +
                    unrecognized_keys.join(', ')
            end

            options = DEFAULT_SETTINGS.merge(options)
            unless options[:push_scope] || options[:metric]
              raise "Can't add a tracer where push_scope is false and metric is false"
            end

            options
          end

          # Default to the class where the method is defined.
          #
          # Example:
          #  Foo._nr_default_metric_name_code('bar') #=> "Custom/#{Foo.name}/bar"
          def _nr_default_metric_name(method_name)
            -> { "Custom/#{self.class._nr_derived_class_name}/#{method_name}" }
          end

          # Checks to see if the method we are attempting to trace
          # actually exists or not. #add_method_tracer can't do
          # anything if the method doesn't exist.
          def newrelic_method_exists?(method_name)
            exists = method_defined?(method_name) || private_method_defined?(method_name)
            ::NewRelic::Agent.logger.error("Did not trace #{_nr_derived_class_name}##{method_name} because that method does not exist") unless exists
            exists
          end

          # Checks to see if we have already traced a method with a
          # given metric by checking to see if the traced method
          # exists. Warns the user if methods are being double-traced
          # to help with debugging custom instrumentation.
          def traced_method_exists?(method_name, metric_name_code)
            exists = _nr_traced_method_module.method_defined?(method_name)
            ::NewRelic::Agent.logger.error("Attempt to trace a method twice with the same metric: Method = #{method_name}, Metric Name = #{metric_name_code}") if exists
            exists
          end

          # Returns an anonymous module that stores prepended trace methods.
          def _nr_traced_method_module
            @_nr_traced_method_module ||= Module.new
          end

          def _nr_derived_class_name
            return self.name if self.name && !self.name.empty?
            return "AnonymousModule" if self.to_s.start_with?("#<Module:")

            # trying to get the "MyClass" portion of "#<Class:MyClass>"
            name = self.to_s[/^#<Class:(.+)>$/, 1]
            if name.start_with?("0x")
              "AnonymousClass"
            elsif name.start_with?("#<Class:")
              "AnonymousClass/Class"
            else
              "#{name}/Class"
            end
          end
        end
        include AddMethodTracer

        # Add a method tracer to the specified method.
        #
        # By default, this will cause invocations of the traced method to be
        # recorded in transaction traces, and in a metric named after the class
        # and method. It will also make the method show up in transaction-level
        # breakdown charts and tables.
        #
        # === Overriding the metric name
        #
        # +metric_name+ is a String or Proc. If a Proc is given, it is bound to
        # the object that called the traced method. For example:
        #
        #     add_method_tracer :foo, -> { "Custom/#{self.class.name}/foo" }
        #
        # This would name the metric according to the class of the runtime
        # instance, as opposed to the class where +foo+ is defined.
        #
        # If not provided, the metric name will be <tt>Custom/ClassName/method_name</tt>.
        #
        # @param method_name [Symbol] the name of the method to trace
        # @param metric_name [String,Proc] the metric name to record calls to
        #   the traced method under. This may be either a String, or a Proc
        #   to be evaluated at call-time in order to determine the metric
        #   name dynamically.
        # @param [Hash] options additional options controlling how the method is
        #   traced.
        # @option options [Boolean] :push_scope (true) If false, the traced method will
        #   not appear in transaction traces or breakdown charts, and it will
        #   only be visible in custom dashboards.
        # @option options [Boolean] :metric (true) If false, the traced method will
        #   only appear in transaction traces, but no metrics will be recorded
        #   for it.
        # @option options [Proc] :code_header ('') Ruby code to be inserted and run
        #   before the tracer begins timing.
        # @option options [Proc] :code_footer ('') Ruby code to be inserted and run
        #   after the tracer stops timing.
        #
        # @example
        #   add_method_tracer :foo
        #
        #   # With a custom metric name
        #   add_method_tracer :foo, "Custom/MyClass/foo"
        #   add_method_tracer :bar, -> { "Custom/#{self.class.name}/bar" }
        #
        #   # Instrument foo only for custom dashboards (not in transaction
        #   # traces or breakdown charts)
        #   add_method_tracer :foo, 'Custom/foo', :push_scope => false
        #
        #   # Instrument foo in transaction traces only
        #   add_method_tracer :foo, 'Custom/foo', :metric => false
        #
        # @api public
        #
        def add_method_tracer(method_name, metric_name_code = nil, options = {})
          ::NewRelic::Agent.add_or_defer_method_tracer(self, method_name, metric_name_code, options)
        end

        # For tests only because tracers must be removed in reverse-order
        # from when they were added, or else other tracers that were added to the same method
        # may get removed as well.
        def remove_method_tracer(method_name) # :nodoc:
          return unless Agent.config[:agent_enabled]
          if _nr_traced_method_module.method_defined?(method_name)
            _nr_traced_method_module.undef_method(method_name)
            ::NewRelic::Agent.logger.debug("removed method tracer #{method_name}\n")
          else
            raise "No tracer on method '#{method_name}'"
          end
        end

        private

        def _nr_add_method_tracer_now(method_name, metric_name, options)
          NewRelic::Agent.record_api_supportability_metric(:add_method_tracer)

          return unless newrelic_method_exists?(method_name)
          metric_name ||= _nr_default_metric_name(method_name)
          return if traced_method_exists?(method_name, metric_name_code)

          visibility = NewRelic::Helper.instance_method_visibility self, method_name

          options = _nr_validate_method_tracer_options(options)

          # Define the prepended tracer method here
          _nr_traced_method_module.module_eval do
            define_method(method_name) do |*args, &block|
              return super(*args, &block) unless NewRelic::Agent.tl_is_execution_traced?

              metric_name_eval = metric_name.kind_of?(Proc) ? instance_exec(&metric_name) : metric_name.to_s

              instance_exec(&options[:code_header]) if options[:code_header].kind_of?(Proc)

              begin
                if options[:push_scope]
                  trace_execution_scoped(metric_name_eval, metric: options[:metric]) { super(*args, &block) }
                else
                  trace_execution_unscoped(metric_name_eval, metric: options[:metric]) { super(*args, &block) }
                end
              ensure
                instance_exec(&options[:code_footer]) if options[:code_footer].kind_of?(Proc)
              end
            end

            ruby2_keywords(method_name) if respond_to?(:ruby2_keywords, true)
          end

          send visibility, method_name
          ::NewRelic::Agent.logger.debug("Traced method: class = #{_nr_derived_class_name},"+
                                         "method = #{method_name}, "+
                                         "metric = '#{metric_name}'")
        end
      end

      # @!parse extend ClassMethods
    end
  end
end
