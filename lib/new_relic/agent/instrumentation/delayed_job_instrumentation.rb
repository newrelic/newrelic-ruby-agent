# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/instrumentation/controller_instrumentation'

DependencyDetection.defer do
  @name = :delayed_job

  depends_on do
    !NewRelic::Agent.config[:disable_dj]
  end

  depends_on do
    # double check because of old JRuby bug
    defined?(::Delayed) && defined?(::Delayed::Job) &&
      Delayed::Job.method_defined?(:invoke_job)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing DelayedJob instrumentation'
  end

  executes do
    Delayed::Job.class_eval do
      include NewRelic::Agent::Instrumentation::ControllerInstrumentation
      if self.instance_methods.include?('name') || self.instance_methods.include?(:name)
        add_transaction_tracer "invoke_job", :category => 'OtherTransaction/DelayedJob', :path => '#{self.name}'
      else
        add_transaction_tracer "invoke_job", :category => 'OtherTransaction/DelayedJob'
      end
    end
  end

  executes do
    Delayed::Job.instance_eval do
      # alias_method is for instance, not class methods. But we still want to
      # call any existing class method we're redefining, so do it the hard way.
      @original_after_fork = method(:after_fork) if respond_to?(:after_fork)

      def after_fork
        NewRelic::Agent.after_fork(:force_reconnect => true)
        @original_after_fork.call() if @original_after_fork
        super
      end
    end
  end
end
