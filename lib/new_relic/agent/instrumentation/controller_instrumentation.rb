# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction'
require 'new_relic/agent/instrumentation/queue_time'
module NewRelic
  module Agent
    # @api public
    module Instrumentation
      # == NewRelic instrumentation for controller actions and tasks
      #
      # This instrumentation is applied to the action controller to collect
      # metrics for every web request.
      #
      # It can also be used to capture performance information for
      # background tasks and other non-web transactions, including
      # detailed transaction traces and traced errors.
      #
      # For details on how to instrument background tasks see
      # ClassMethods#add_transaction_tracer and
      # #perform_action_with_newrelic_trace
      #
      # @api public
      #
      module ControllerInstrumentation

        def self.included(clazz) # :nodoc:
          clazz.extend(ClassMethods)
        end

        # This module is for importing stubs when the agent is disabled
        module ClassMethodsShim # :nodoc:
          def newrelic_ignore(*args); end
          def newrelic_ignore_apdex(*args); end
          def newrelic_ignore_enduser(*args); end
        end

        module Shim # :nodoc:
          def self.included(clazz)
            clazz.extend(ClassMethodsShim)
          end
          def newrelic_notice_error(*args); end
          def new_relic_trace_controller_action(*args); yield; end
          def perform_action_with_newrelic_trace(*args); yield; end
        end

        module ClassMethods
          # Have NewRelic ignore actions in this controller.  Specify the actions as hash options
          # using :except and :only.  If no actions are specified, all actions are ignored.
          #
          # @api public
          #
          def newrelic_ignore(specifiers={})
            newrelic_ignore_aspect('do_not_trace', specifiers)
          end
          # Have NewRelic omit apdex measurements on the given actions.  Typically used for
          # actions that are not user facing or that skew your overall apdex measurement.
          # Accepts :except and :only options, as with #newrelic_ignore.
          #
          # @api public
          #
          def newrelic_ignore_apdex(specifiers={})
            newrelic_ignore_aspect('ignore_apdex', specifiers)
          end

          # @api public
          def newrelic_ignore_enduser(specifiers={})
            newrelic_ignore_aspect('ignore_enduser', specifiers)
          end

          def newrelic_ignore_aspect(property, specifiers={}) # :nodoc:
            if specifiers.empty?
              self.newrelic_write_attr property, true
            elsif ! (Hash === specifiers)
              ::NewRelic::Agent.logger.error "newrelic_#{property} takes an optional hash with :only and :except lists of actions (illegal argument type '#{specifiers.class}')"
            else
              self.newrelic_write_attr property, specifiers
            end
          end

          # Should be monkey patched into the controller class implemented
          # with the inheritable attribute mechanism.
          def newrelic_write_attr(attr_name, value) # :nodoc:
            instance_variable_set "@#{attr_name}", value
          end

          def newrelic_read_attr(attr_name) # :nodoc:
            instance_variable_get "@#{attr_name}"
          end

          # Add transaction tracing to the given method.  This will treat
          # the given method as a main entrypoint for instrumentation, just
          # like controller actions are treated by default.  Useful especially
          # for background tasks.
          #
          # Example for background job:
          #   class Job
          #     include NewRelic::Agent::Instrumentation::ControllerInstrumentation
          #     def run(task)
          #        ...
          #     end
          #     # Instrument run so tasks show up under task.name.  Note single
          #     # quoting to defer eval to runtime.
          #     add_transaction_tracer :run, :name => '#{args[0].name}'
          #   end
          #
          # Here's an example of a controller that uses a dispatcher
          # action to invoke operations which you want treated as top
          # level actions, so they aren't all lumped into the invoker
          # action.
          #
          #   MyController < ActionController::Base
          #     include NewRelic::Agent::Instrumentation::ControllerInstrumentation
          #     # dispatch the given op to the method given by the service parameter.
          #     def invoke_operation
          #       op = params['operation']
          #       send op
          #     end
          #     # Ignore the invoker to avoid double counting
          #     newrelic_ignore :only => 'invoke_operation'
          #     # Instrument the operations:
          #     add_transaction_tracer :print
          #     add_transaction_tracer :show
          #     add_transaction_tracer :forward
          #   end
          #
          # Here's an example of how to pass contextual information into the transaction
          # so it will appear in transaction traces:
          #
          #   class Job
          #     include NewRelic::Agent::Instrumentation::ControllerInstrumentation
          #     def process(account)
          #        ...
          #     end
          #     # Include the account name in the transaction details.  Note the single
          #     # quotes to defer eval until call time.
          #     add_transaction_tracer :process, :params => '{ :account_name => args[0].name }'
          #   end
          #
          # See NewRelic::Agent::Instrumentation::ControllerInstrumentation#perform_action_with_newrelic_trace
          # for the full list of available options.
          #
          # @api public
          #
          def add_transaction_tracer(method, options={})
            # The metric path:
            options[:name] ||= method.to_s
            # create the argument list:
            options_arg = []
            options.each do |key, value|
              valuestr = case
                         when value.is_a?(Symbol)
                           value.inspect
                         when key == :params
                           value.to_s
                         else
                           %Q["#{value.to_s}"]
                         end
              options_arg << %Q[:#{key} => #{valuestr}]
            end
            traced_method, punctuation = method.to_s.sub(/([?!=])$/, ''), $1
            visibility = NewRelic::Helper.instance_method_visibility self, method

            without_method_name = "#{traced_method.to_s}_without_newrelic_transaction_trace#{punctuation}"
            with_method_name = "#{traced_method.to_s}_with_newrelic_transaction_trace#{punctuation}"

            if NewRelic::Helper.instance_methods_include?(self, with_method_name)
              ::NewRelic::Agent.logger.warn("Transaction tracer already in place for class = #{self.name}, method = #{method.to_s}, skipping")
              return
            end

            class_eval <<-EOC
              def #{traced_method.to_s}_with_newrelic_transaction_trace#{punctuation}(*args, &block)
                perform_action_with_newrelic_trace(#{options_arg.join(',')}) do
                  #{traced_method.to_s}_without_newrelic_transaction_trace#{punctuation}(*args, &block)
                 end
              end
            EOC
            alias_method without_method_name, method.to_s
            alias_method method.to_s, with_method_name
            send visibility, method
            send visibility, with_method_name
            ::NewRelic::Agent.logger.debug("Traced transaction: class = #{self.name}, method = #{method.to_s}, options = #{options.inspect}")
          end
        end

        class TransactionNamer
          def initialize(traced_obj)
            @traced_obj = traced_obj
            if (@traced_obj.is_a?(Class) || @traced_obj.is_a?(Module))
              @traced_class_name = @traced_obj.name
            else
              @traced_class_name = @traced_obj.class.name
            end
          end

          def name(options={})
            name = "#{category_name(options[:category])}/#{path_name(options)}"
          end

          def category_name(type = nil)
            type ||= Transaction.current && Transaction.current.type
            case type
            when :controller, nil then 'Controller'
            when :task then 'OtherTransaction/Background'
            when :rack then 'Controller/Rack'
            when :uri then 'Controller'
            when :sinatra then 'Controller/Sinatra'
              # for internal use only
            else type.to_s
            end
          end

          def path_name(options={})
            # if we have the path, use the path
            path = options[:path]

            class_name = options[:class_name] || @traced_class_name

            # if we have an explicit action name option, use that
            if options[:name]
              path ||= [ class_name, options[:name] ].compact.join('/')
            end

            # if newrelic_metric_path() is defined, use that
            if @traced_obj.respond_to?(:newrelic_metric_path)
              path ||= @traced_obj.newrelic_metric_path
            end

            # fall back on just the traced class name
            path ||= class_name

            return path
          end
        end

        # Yield to the given block with NewRelic tracing.  Used by
        # default instrumentation on controller actions in Rails and Merb.
        # But it can also be used in custom instrumentation of controller
        # methods and background tasks.
        #
        # This is the method invoked by instrumentation added by the
        # <tt>ClassMethods#add_transaction_tracer</tt>.
        #
        # Here's a more verbose version of the example shown in
        # <tt>ClassMethods#add_transaction_tracer</tt> using this method instead of
        # #add_transaction_tracer.
        #
        # Below is a controller with an +invoke_operation+ action which
        # dispatches to more specific operation methods based on a
        # parameter (very dangerous, btw!).  With this instrumentation,
        # the +invoke_operation+ action is ignored but the operation
        # methods show up in New Relic as if they were first class controller
        # actions
        #
        #   MyController < ActionController::Base
        #     include NewRelic::Agent::Instrumentation::ControllerInstrumentation
        #     # dispatch the given op to the method given by the service parameter.
        #     def invoke_operation
        #       op = params['operation']
        #       perform_action_with_newrelic_trace(:name => op) do
        #         send op, params['message']
        #       end
        #     end
        #     # Ignore the invoker to avoid double counting
        #     newrelic_ignore :only => 'invoke_operation'
        #   end
        #
        #
        # When invoking this method explicitly as in the example above, pass in a
        # block to measure with some combination of options:
        #
        # * <tt>:category => :controller</tt> indicates that this is a
        #   controller action and will appear with all the other actions.  This
        #   is the default.
        # * <tt>:category => :task</tt> indicates that this is a
        #   background task and will show up in New Relic with other background
        #   tasks instead of in the controllers list
        # * <tt>:category => :rack</tt> if you are instrumenting a rack
        #   middleware call.  The <tt>:name</tt> is optional, useful if you
        #   have more than one potential transaction in the #call.
        # * <tt>:category => :uri</tt> indicates that this is a
        #   web transaction whose name is a normalized URI, where  'normalized'
        #   means the URI does not have any elements with data in them such
        #   as in many REST URIs.
        # * <tt>:name => action_name</tt> is used to specify the action
        #   name used as part of the metric name
        # * <tt>:params => {...}</tt> to provide information about the context
        #   of the call, used in transaction trace display, for example:
        #   <tt>:params => { :account => @account.name, :file => file.name }</tt>
        #   These are treated similarly to request parameters in web transactions.
        #
        # Seldomly used options:
        #
        # * <tt>:force => true</tt> indicates you should capture all
        #   metrics even if the #newrelic_ignore directive was specified
        # * <tt>:class_name => aClass.name</tt> is used to override the name
        #   of the class when used inside the metric name.  Default is the
        #   current class.
        # * <tt>:path => metric_path</tt> is *deprecated* in the public API.  It
        #   allows you to set the entire metric after the category part.  Overrides
        #   all the other options.
        # * <tt>:request => Rack::Request#new(env)</tt> is used to pass in a
        #   request object that may respond to uri and referer.
        #
        # If a single argument is passed in, it is treated as a metric
        # path.  This form is deprecated.
        #
        # @api public
        #
        def perform_action_with_newrelic_trace(*args, &block)
          request = newrelic_request(args)
          NewRelic::Agent::TransactionState.reset(request)

          # Skip instrumentation based on the value of 'do_not_trace' and if
          # we aren't calling directly with a block.
          if !block_given? && do_not_trace?
            # Also ignore all instrumentation in the call sequence
            NewRelic::Agent.disable_all_tracing do
              return perform_action_without_newrelic_trace(*args)
            end
          end

          control = NewRelic::Control.instance
          return perform_action_with_newrelic_profile(args, &block) if control.profiling?

          txn = _start_transaction(block_given? ? args : [])
          begin
            options = { :force => txn.force_flag, :transaction => true }
            return yield if !(NewRelic::Agent.is_execution_traced? || options[:force])
            options[:metric] = true if options[:metric].nil?
            options[:deduct_call_time_from_parent] = true if options[:deduct_call_time_from_parent].nil?
            _, expected_scope = NewRelic::Agent::MethodTracer::TraceExecutionScoped.trace_execution_scoped_header(options, txn.start_time.to_f)

            begin
              NewRelic::Agent::BusyCalculator.dispatcher_start txn.start_time
              if block_given?
                yield
              else
                perform_action_without_newrelic_trace(*args)
              end
            rescue => e
              txn.notice_error(e)
              raise
            end

          ensure
            end_time = Time.now

            txn.freeze_name
            metric_names = Array(recorded_metrics(txn))
            txn_name = metric_names.shift

            NewRelic::Agent::MethodTracer::TraceExecutionScoped.trace_execution_scoped_footer(txn.start_time.to_f, txn_name, metric_names, expected_scope, options, end_time.to_f)
            NewRelic::Agent::BusyCalculator.dispatcher_finish(end_time)
            txn.record_apdex(end_time) unless ignore_apdex?
            txn = Transaction.stop(txn_name, end_time)

            NewRelic::Agent::TransactionState.get.request_ignore_enduser = true if ignore_enduser?
          end
        end

        def recorded_metrics(txn)
          metric_parser = NewRelic::MetricParser::MetricParser.for_metric_named(txn.name)
          metrics = [txn.name]
          metrics += metric_parser.summary_metrics unless txn.has_parent?
          metrics
        end

        protected

        def newrelic_request(args)
          opts = args.first
          # passed as a parameter to add_transaction_tracer
          if opts.respond_to?(:keys) && opts.respond_to?(:[]) && opts[:request]
            opts[:request]
          # in a Rack app
          elsif opts.respond_to?(:keys) && opts.respond_to?(:[]) &&
              opts['rack.version']
            Rack::Request.new(args)
          # in a Rails app
          elsif self.respond_to?(:request)
            self.request
          end
        end

        # Should be implemented in the dispatcher class
        def newrelic_response_code; end

        def newrelic_request_headers
          self.respond_to?(:request) && self.request.respond_to?(:headers) && self.request.headers
        end

        # overrideable method to determine whether to trace an action
        # or not - you may override this in your controller and supply
        # your own logic for ignoring transactions.
        def do_not_trace?
          _is_filtered?('do_not_trace')
        end

        # overrideable method to determine whether to trace an action
        # for purposes of apdex measurement - you can use this to
        # ignore things like api calls or other fast non-user-facing
        # actions
        def ignore_apdex?
          _is_filtered?('ignore_apdex')
        end

        def ignore_enduser?
          _is_filtered?('ignore_enduser')
        end

        private

        # Profile the instrumented call.  Dev mode only.  Experimental
        # - should definitely not be used on production applications
        def perform_action_with_newrelic_profile(args)
          txn = _start_transaction(block_given? ? args : [])
          val = nil
          NewRelic::Agent.trace_execution_scoped txn.metric_name do
            NewRelic::Agent.disable_all_tracing do
              # turn on profiling
              profile = RubyProf.profile do
                if block_given?
                  val = yield
                else
                  val = perform_action_without_newrelic_trace(*args)
                end
              end
              NewRelic::Agent.instance.transaction_sampler.notice_profile profile
            end
          end
          return val
        ensure
          txn.pop
        end

        # Write a transaction onto a thread local if there isn't already one there.
        # If there is one, just update it.
        def _start_transaction(args) # :nodoc:
          # If a block was passed in, then the arguments represent options for the instrumentation,
          # not app method arguments.
          options = {}
          if args.any?
            if args.last.is_a?(Hash)
              options = args.pop
            end
            available_params = options[:params] || {}
            options[:name] ||= args.first
          else
            available_params = self.respond_to?(:params) ? self.params : {}
          end

          options[:request] ||= self.request if self.respond_to? :request
          options[:filtered_params] = (respond_to? :filter_parameters) ? filter_parameters(available_params) : available_params
          category = options[:category] || :controller
          txn = Transaction.start(category, options)
          txn.name = TransactionNamer.new(self).name(options)

          txn.apdex_start = _detect_upstream_wait(txn.start_time)
          _record_queue_length

          return txn
        end

        # Filter out a request if it matches one of our parameters for
        # ignoring it - the key is either 'do_not_trace' or 'ignore_apdex'
        def _is_filtered?(key)
          ignore_actions = self.class.newrelic_read_attr(key) if self.class.respond_to? :newrelic_read_attr
          case ignore_actions
          when nil; false
          when Hash
            only_actions = Array(ignore_actions[:only])
            except_actions = Array(ignore_actions[:except])
            only_actions.include?(action_name.to_sym) || (except_actions.any? && !except_actions.include?(action_name.to_sym))
          else
            true
          end
        end
        # Take a guess at a measure representing the number of requests waiting in mongrel
        # or heroku.
        def _record_queue_length
          if newrelic_request_headers
            if queue_depth = newrelic_request_headers['HTTP_X_HEROKU_QUEUE_DEPTH']
              queue_depth = queue_depth.to_i rescue nil
            elsif mongrel = NewRelic::Control.instance.local_env.mongrel
              # Always subtrace 1 for the active mongrel
              queue_depth = [mongrel.workers.list.length.to_i - 1, 0].max rescue nil
            end
            NewRelic::Agent.record_metric('Mongrel/Queue Length', queue_depth) if queue_depth
          end
        end

        # Return a Time instance representing the upstream start time.
        # now is a Time instance to fall back on if no other candidate
        # for the start time is found.
        def _detect_upstream_wait(now)
          if newrelic_request_headers
            queue_start = QueueTime.parse_frontend_timestamp(newrelic_request_headers, now)
            QueueTime.record_frontend_metrics(queue_start, now) if queue_start
          end
          queue_start || now
        rescue => e
          ::NewRelic::Agent.logger.error("Error detecting upstream wait time:", e)
          now
        end
      end
    end
  end
end
