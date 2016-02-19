# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  @name = :rails5_action_cable

  depends_on do
    defined?(::Rails) &&
     ::Rails::VERSION::MAJOR.to_i == 5 &&
     defined?(::ActionCable)
  end

  depends_on do
    # !NewRelic::Agent.config[:disable_view_instrumentation] &&
    #   !NewRelic::Agent::Instrumentation::ActionViewSubscriber.subscribed?
    true
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Rails 5 ActionCable'
  end

  executes do
    ::ActionCable::Channel::Base.class_eval do
      include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation
      alias_method :perform_action_without_newrelic, :perform_action

      def perform_action data
        action = extract_action data
        NewRelic::Agent.logger.info "Recording Action cable txn: #{action}"
        perform_action_with_newrelic_trace :category => :controller, :name => action do
          perform_action_without_newrelic data
        end
      end
    end
  end
end
