# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction'
require 'new_relic/agent/instrumentation/queue_time'
require 'new_relic/agent/instrumentation/ignore_actions'
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

        NR_DO_NOT_TRACE_KEY   = :'@do_not_trace'   unless defined?(NR_DO_NOT_TRACE_KEY  )
        NR_IGNORE_APDEX_KEY   = :'@ignore_apdex'   unless defined?(NR_IGNORE_APDEX_KEY  )
        NR_IGNORE_ENDUSER_KEY = :'@ignore_enduser' unless defined?(NR_IGNORE_ENDUSER_KEY)
        NR_DEFAULT_OPTIONS    = {}.freeze          unless defined?(NR_DEFAULT_OPTIONS   )

        # @api public
        module ClassMethods
          # Have NewRelic ignore actions in this controller.  Specify the actions as hash options
          # using :except and :only.  If no actions are specified, all actions are ignored.
          #
          # @api public
          #
          def newrelic_ignore(specifiers={})
            newrelic_ignore_aspect(NR_DO_NOT_TRACE_KEY, specifiers)
          end
          # Have NewRelic omit apdex measurements on the given actions.  Typically used for
          # actions that are not user facing or that skew your overall apdex measurement.
          # Accepts :except and :only options, as with #newrelic_ignore.
          #
          # @api public
          #
          def newrelic_ignore_apdex(specifiers={})
            newrelic_ignore_aspect(NR_IGNORE_APDEX_KEY, specifiers)
          end

          # @api public
          def newrelic_ignore_enduser(specifiers={})
            newrelic_ignore_aspect(NR_IGNORE_ENDUSER_KEY, specifiers)
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
            instance_variable_set(attr_name, value)
          end

          def newrelic_read_attr(attr_name) # :nodoc:
            instance_variable_get(attr_name)
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

            argument_list = generate_argument_list(options)
            traced_method, punctuation = parse_punctuation(method)
            with_method_name, without_method_name = build_method_names(traced_method, punctuation)

            if already_added_transaction_tracer?(self, with_method_name)
              ::NewRelic::Agent.logger.warn("Transaction tracer already in place for class = #{self.name}, method = #{method.to_s}, skipping")
              return
            end

            class_eval <<-EOC
              def #{with_method_name}(*args, &block)
                perform_action_with_newrelic_trace(#{argument_list.join(',')}) do
                  #{without_method_name}(*args, &block)
                 end
              end
            EOC

            visibility = NewRelic::Helper.instance_method_visibility self, method

            alias_method without_method_name, method.to_s
            alias_method method.to_s, with_method_name
            send visibility, method
            send visibility, with_method_name
            ::NewRelic::Agent.logger.debug("Traced transaction: class = #{self.name}, method = #{method.to_s}, options = #{options.inspect}")
          end

          def parse_punctuation(method)
            [method.to_s.sub(/([?!=])$/, ''), $1]
          end

          def generate_argument_list(options)
            options.map do |key, value|
              value = if value.is_a?(Symbol)
                value.inspect
              elsif key == :params
                value.to_s
              else
                %Q["#{value.to_s}"]
              end

              %Q[:#{key} => #{value}]
            end
          end

          def build_method_names(traced_method, punctuation)
            [ "#{traced_method.to_s}_with_newrelic_transaction_trace#{punctuation}",
              "#{traced_method.to_s}_without_newrelic_transaction_trace#{punctuation}" ]
          end

          def already_added_transaction_tracer?(target, with_method_name)
            if NewRelic::Helper.instance_methods_include?(target, with_method_name)
              true
            else
              false
            end
          end
        end

        class TransactionNamer
          def self.txn_name(txn, traced_obj, category, options={})
            "#{prefix_for_category(txn, category)}#{path_name(traced_obj, options)}"
          end

          def self.prefix_for_category(txn, category = nil)
            category ||= (txn && txn.best_category)
            case category
            when :controller then ::NewRelic::Agent::Transaction::CONTROLLER_PREFIX
            when :task       then ::NewRelic::Agent::Transaction::TASK_PREFIX
            when :rack       then ::NewRelic::Agent::Transaction::RACK_PREFIX
            when :uri        then ::NewRelic::Agent::Transaction::CONTROLLER_PREFIX
            when :sinatra    then ::NewRelic::Agent::Transaction::SINATRA_PREFIX
            when :middleware then ::NewRelic::Agent::Transaction::MIDDLEWARE_PREFIX
            else "#{category.to_s}/" # for internal use only
            end
          end

          def self.path_name(traced_obj, options={})
            return options[:path] if options[:path]

            class_name = class_name(traced_obj, options)
            if options[:name]
              if class_name
                "#{class_name}/#{options[:name]}"
              else
                options[:name]
              end
            elsif traced_obj.respond_to?(:newrelic_metric_path)
              traced_obj.newrelic_metric_path
            else
              class_name
            end
          end

          def self.class_name(traced_obj, options={})
            return options[:class_name] if options[:class_name]
            if (traced_obj.is_a?(Class) || traced_obj.is_a?(Module))
              traced_obj.name
            else
              traced_obj.class.name
            end
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
        # * <tt>:category => :middleware</tt> if you are instrumenting a rack
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
        # * <tt>:class_name => aClass.name</tt> is used to override the name
        #   of the class when used inside the metric name.  Default is the
        #   current class.
        # * <tt>:path => metric_path</tt> is *deprecated* in the public API.  It
        #   allows you to set the entire metric after the category part.  Overrides
        #   all the other options.
        # * <tt>:request => Rack::Request#new(env)</tt> is used to pass in a
        #   request object that may respond to uri and referer.
        #
        # @api public
        #
        def perform_action_with_newrelic_trace(*args, &block) #THREAD_LOCAL_ACCESS
          state = NewRelic::Agent::TransactionState.tl_get
          state.request = newrelic_request(args)

          # Skip instrumentation based on the value of 'do_not_trace?' and if
          # we aren't calling directly with a block.
          if !block_given? && do_not_trace?
            state.current_transaction.ignore! if state.current_transaction
            NewRelic::Agent.disable_all_tracing do
              return perform_action_without_newrelic_trace(*args)
            end
          end

          return yield unless state.is_execution_traced?

          # If a block was passed in, then the arguments represent options for
          # the instrumentation, not app method arguments.
          trace_options = NR_DEFAULT_OPTIONS

          if block_given?
            trace_options    = args.last if args.last.is_a?(Hash)
            available_params = trace_options[:params]
          else
            available_params = respond_to?(:params) && params
          end

          category    = trace_options[:category] || :controller
          txn_options = create_transaction_options(trace_options, available_params)
          txn_options[:transaction_name] = TransactionNamer.txn_name(nil, self, category, trace_options)
          txn_options[:apdex_start_time] = detect_queue_start_time(state)

          begin
            txn = Transaction.start(state, category, txn_options)

            begin
              if block_given?
                yield
              else
                perform_action_without_newrelic_trace(*args)
              end
            rescue => e
              NewRelic::Agent.notice_error(e)
              raise
            end

          ensure
            if txn
              txn.ignore_apdex!   if ignore_apdex?
              txn.ignore_enduser! if ignore_enduser?
            end
            Transaction.stop(state)
          end
        end

        protected

        def newrelic_request(args)
          opts = args.first
          # passed as a parameter to add_transaction_tracer
          if opts.respond_to?(:keys) && opts.respond_to?(:[]) && opts[:request]
            opts[:request]
          # in a Rails app
          elsif self.respond_to?(:request)
            self.request
          end
        end

        # Should be implemented in the dispatcher class
        def newrelic_response_code; end

        def newrelic_request_headers(state)
          request = state.request
          if request
            if request.respond_to?(:headers)
              request.headers
            elsif request.respond_to?(:env)
              request.env
            end
          end
        end

        # overrideable method to determine whether to trace an action
        # or not - you may override this in your controller and supply
        # your own logic for ignoring transactions.
        def do_not_trace?
          _is_filtered?(NR_DO_NOT_TRACE_KEY)
        end

        # overrideable method to determine whether to trace an action
        # for purposes of apdex measurement - you can use this to
        # ignore things like api calls or other fast non-user-facing
        # actions
        def ignore_apdex?
          _is_filtered?(NR_IGNORE_APDEX_KEY)
        end

        def ignore_enduser?
          _is_filtered?(NR_IGNORE_ENDUSER_KEY)
        end

        private

        def create_transaction_options(trace_options, available_params)
          txn_options = {}
          txn_options[:request]   = trace_options[:request]
          txn_options[:request] ||= request if respond_to?(:request)

          if available_params
            txn_options[:filtered_params] = (respond_to?(:filter_parameters)) ? filter_parameters(available_params) : available_params
          end

          txn_options
        end

        # Filter out a request if it matches one of our parameters for
        # ignoring it - the key is either NR_DO_NOT_TRACE_KEY or NR_IGNORE_APDEX_KEY
        def _is_filtered?(key)
          name = if respond_to?(:action_name)
            action_name
          else
            :'[action_name_missing]'
          end

          NewRelic::Agent::Instrumentation::IgnoreActions.is_filtered?(
            key,
            self.class,
            name)
        end

        def detect_queue_start_time(state)
          headers = newrelic_request_headers(state)

          QueueTime.parse_frontend_timestamp(headers) if headers
        end
      end
    end
  end
end
