# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  @name = :rails2_error

  depends_on do
    defined?(ActionController) && defined?(ActionController::Base)
  end

  depends_on do
    defined?(::Rails) && ::Rails::VERSION::MAJOR.to_i == 2
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Rails 2 Error instrumentation'
  end

  executes do

    ActionController::Base.class_eval do

      # Make a note of an exception associated with the currently executing
      # controller action.  Note that this used to be available on Object
      # but we replaced that global method with NewRelic::Agent#notice_error.
      # Use that one instead.
      #
      # @api public
      # @deprecated
      def newrelic_notice_error(exception, custom_params = {})
        NewRelic::Agent::Deprecator.deprecate("ActionController#newrelic_notice_error",
                                              "NewRelic::Agent#notice_error")

        NewRelic::Agent::Transaction.notice_error exception, :custom_params => custom_params
      end

      def rescue_action_with_newrelic_trace(exception)
        rescue_action_without_newrelic_trace exception
        NewRelic::Agent::Transaction.notice_error exception
      end

      # Compare with #alias_method_chain, which is not available in
      # Rails 1.1:
      alias_method :rescue_action_without_newrelic_trace, :rescue_action
      alias_method :rescue_action, :rescue_action_with_newrelic_trace
      protected :rescue_action

    end
  end
end
