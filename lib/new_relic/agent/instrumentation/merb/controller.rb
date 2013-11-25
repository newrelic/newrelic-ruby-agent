# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'set'

DependencyDetection.defer do
  @name = :merb_controller

  depends_on do
    defined?(Merb) && defined?(Merb::Controller)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Merb Controller instrumentation'
  end

  executes do
    require 'merb-core/controller/merb_controller'

    Merb::Controller.class_eval do
      include NewRelic::Agent::Instrumentation::ControllerInstrumentation

      class_inheritable_accessor :do_not_trace
      class_inheritable_accessor :ignore_apdex

      def self.newrelic_write_attr(attr_name, value) # :nodoc:
        self.send "#{attr_name}=", attr_name, value
      end

      def self.newrelic_read_attr(attr_name) # :nodoc:
        self.send attr_name
      end

      # determine the path that is used in the metric name for
      # the called controller action
      def newrelic_metric_path
        "#{controller_name}/#{action_name}"
      end

      protected

      alias_method :perform_action_without_newrelic_trace, :_dispatch
      alias_method :_dispatch, :perform_action_with_newrelic_trace
    end
  end
end
