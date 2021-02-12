# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.


module NewRelic
  module Agent
    module Instrumentation
      module DelayedJobPrepend

        def initialize(*args)
          super
          worker_name = case
                        when self.respond_to?(:name) then self.name
                        when self.class.respond_to?(:default_name) then self.class.default_name
                        end
          NewRelic::DelayedJobInjection.worker_name = worker_name
  
          if defined?(::Delayed::Job) && ::Delayed::Job.method_defined?(:invoke_job) &&
            !(::Delayed::Job.method_defined?(:invoke_job_without_new_relic) )
  
            ::NewRelic::Agent.logger.info 'Installing DelayedJob instrumentation [part 2/2]'
            Delayed::Job.prepend ::NewRelic::Agent::Instrumentation::DelayedJobTracerPrepend
            NewRelic::Control.instance.init_plugin :dispatcher => :delayed_job
          else
            NewRelic::Agent.logger.warn("Did not find a Delayed::Job class responding to invoke_job, aborting DJ instrumentation")
          end
        end
  
      end

      module DelayedJobTracerPrepend
        include NewRelic::Agent::Instrumentation::ControllerInstrumentation

        NR_TRANSACTION_CATEGORY = 'OtherTransaction/DelayedJob'.freeze

        def invoke_job(*args, &block)
          options = {
            :category => NR_TRANSACTION_CATEGORY,
            :path => ::NewRelic::Agent::Instrumentation::DelayedJob::Naming.name_from_payload(payload_object)
          }

          perform_action_with_newrelic_trace(options) do
            super
          end
        end

      end
    end
  end
end
