# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic::Agent::Instrumentation
  module DelayedJob
    module Chain
      def self.instrument!
        Delayed::Worker.class_eval do
          def initialize_with_new_relic(*args)
            initialize_without_new_relic(*args)
            worker_name = case
                          when self.respond_to?(:name) then self.name
                          when self.class.respond_to?(:default_name) then self.class.default_name
                          end
            NewRelic::DelayedJobInjection.worker_name = worker_name
    
            if defined?(::Delayed::Job) && ::Delayed::Job.method_defined?(:invoke_job) &&
              !(::Delayed::Job.method_defined?(:invoke_job_without_new_relic) )
    
              ::NewRelic::Agent.logger.info 'Installing DelayedJob instrumentation [part 2/2]'
              install_newrelic_job_tracer
              NewRelic::Control.instance.init_plugin :dispatcher => :delayed_job
            else
              NewRelic::Agent.logger.warn("Did not find a Delayed::Job class responding to invoke_job, aborting DJ instrumentation")
            end
          end
    
          alias initialize_without_new_relic initialize
          alias initialize initialize_with_new_relic
    
    
          def install_newrelic_job_tracer
            Delayed::Job.class_eval do
              include NewRelic::Agent::Instrumentation::ControllerInstrumentation
    
              alias_method :invoke_job_without_new_relic, :invoke_job
    
              def invoke_job(*args, &block)
                options = {
                  :category => 'OtherTransaction/DelayedJob'.freeze,
                  :path => ::NewRelic::Agent::Instrumentation::DelayedJob::Naming.name_from_payload(payload_object)
                }
    
                perform_action_with_newrelic_trace(options) do
                  invoke_job_without_new_relic(*args, &block)
                end
              end
    
            end
          end
        end
      end
    end
  end
end