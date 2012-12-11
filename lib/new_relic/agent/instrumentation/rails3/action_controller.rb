module NewRelic
  module Agent
    module Instrumentation
      module Rails3
        module ActionController
          def self.newrelic_write_attr(attr_name, value) # :nodoc:
            write_inheritable_attribute(attr_name, value)
          end

          def self.newrelic_read_attr(attr_name) # :nodoc:
            read_inheritable_attribute(attr_name)
          end

          # determine the path that is used in the metric name for
          # the called controller action
          def newrelic_metric_path(action_name_override = nil)
            action_part = action_name_override || action_name
            if action_name_override || self.class.action_methods.include?(action_part)
              "#{self.class.controller_path}/#{action_part}"
            else
              "#{self.class.controller_path}/(other)"
            end
          end

          def process_action(*args)
            # skip instrumentation if we are in an ignored action
            if _is_filtered?('do_not_trace')
              NewRelic::Agent.disable_all_tracing do
                return super
              end
            end

            perform_action_with_newrelic_trace(:category => :controller, :name => self.action_name, :path => newrelic_metric_path, :params => request.filtered_parameters, :class_name => self.class.name)  do
              super
            end
          end

        end

        module ActionView
          module NewRelic
            extend self
            def template_metric(identifier, options = {})
              if options[:file]
                "file"
              elsif identifier.nil?
                "(unknown)"
              elsif identifier.include? '/' # this is a filepath
                identifier.split('/')[-2..-1].join('/')
              else
                identifier
              end
            end
            def render_type(file_path)
              file = File.basename(file_path)
              if file.starts_with?('_')
                return 'Partial'
              else
                return 'Rendering'
              end
            end
          end
        end
      end
    end
  end
end

DependencyDetection.defer do
  @name = :rails3_controller

  depends_on do
    defined?(::Rails) && ::Rails::VERSION::MAJOR.to_i == 3
  end

  depends_on do
    defined?(ActionController) && defined?(ActionController::Base)
  end

  executes do
    NewRelic::Agent.logger.debug 'Installing Rails 3 Controller instrumentation'
  end

  executes do
    class ActionController::Base
      include NewRelic::Agent::Instrumentation::ControllerInstrumentation
      include NewRelic::Agent::Instrumentation::Rails3::ActionController
    end
  end
end
DependencyDetection.defer do
  @name = :rails30_view

  depends_on do
    defined?(::Rails) && ::Rails::VERSION::MAJOR.to_i == 3 && ::Rails::VERSION::MINOR.to_i == 0
  end

  depends_on do
    !NewRelic::Agent.config[:disable_view_instrumentation]
  end

  executes do
    NewRelic::Agent.logger.debug 'Installing Rails 3.0 view instrumentation'
  end

  executes do
    ActionView::Template.class_eval do
      include NewRelic::Agent::MethodTracer
      def render_with_newrelic(*args, &block)
        options = if @virtual_path && @virtual_path.starts_with?('/') # file render
          {:file => true }
        else
          {}
        end
        str = "View/#{NewRelic::Agent::Instrumentation::Rails3::ActionView::NewRelic.template_metric(@identifier, options)}/#{NewRelic::Agent::Instrumentation::Rails3::ActionView::NewRelic.render_type(@identifier)}"
        trace_execution_scoped str do
          render_without_newrelic(*args, &block)
        end
      end

      alias_method :render_without_newrelic, :render
      alias_method :render, :render_with_newrelic

    end
  end
end

DependencyDetection.defer do
  @name = :rails31_view

  # We can't be sure that this wil work with future versions of Rails 3.
  # Currently enabled for Rails 3.1 and 3.2
  depends_on do
    defined?(::Rails) && ::Rails::VERSION::MAJOR.to_i == 3 && ([1,2].member?(::Rails::VERSION::MINOR.to_i))
  end

  depends_on do
    !NewRelic::Agent.config[:disable_view_instrumentation]
  end

  executes do
    NewRelic::Agent.logger.debug 'Installing Rails 3.1/3.2 view instrumentation'
  end

  executes do
    ActionView::TemplateRenderer.class_eval do
      include NewRelic::Agent::MethodTracer
      # namespaced helper methods

      def render_with_newrelic(context, options)
        # This is needed for rails 3.2 compatibility
        @details = extract_details(options) if respond_to? :extract_details
        identifier = determine_template(options) ? determine_template(options).identifier : nil
        str = "View/#{NewRelic::Agent::Instrumentation::Rails3::ActionView::NewRelic.template_metric(identifier, options)}/Rendering"
        trace_execution_scoped str do
          render_without_newrelic(context, options)
        end
      end

      alias_method :render_without_newrelic, :render
      alias_method :render, :render_with_newrelic
    end

    ActionView::PartialRenderer.class_eval do
      include NewRelic::Agent::MethodTracer

      def render_with_newrelic(*args, &block)
        setup(*args, &block)
        identifier = find_partial ? find_partial.identifier : nil
        str = "View/#{NewRelic::Agent::Instrumentation::Rails3::ActionView::NewRelic.template_metric(identifier)}/Partial"
        trace_execution_scoped str do
          render_without_newrelic(*args, &block)
        end
      end

      alias_method :render_without_newrelic, :render
      alias_method :render, :render_with_newrelic
    end
  end
end
