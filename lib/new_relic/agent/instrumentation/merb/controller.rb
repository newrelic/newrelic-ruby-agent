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

      # determine the path that is used in the metric name for
      # the called controller action
      def newrelic_metric_path
        "#{controller_name}/#{action_name}"
      end

      prepend Module.new do
        protected

        def _dispatch(*args)
          options = {}
          options[:params] = params
          perform_action_with_newrelic_trace(options) do
            super(*args)
          end
        end
      end
    end
  end
end
