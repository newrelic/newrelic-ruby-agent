# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative 'rake_instrumentation'

module NewRelic::Agent::Instrumentation
  module Rake
    module Chain 
      def self.instrument!
        ::Rake::Task.class_eval do 
          alias_method :invoke_without_newrelic, :invoke

          def invoke(*args)
            unless NewRelic::Agent::Instrumentation::RakeInstrumentation.should_trace? name
              return invoke_without_newrelic(*args)
            end
  
            begin
              timeout = NewRelic::Agent.config[:'rake.connect_timeout']
              NewRelic::Agent.instance.wait_on_connect(timeout)
            rescue => e
              NewRelic::Agent.logger.error("Exception in wait_on_connect", e)
              return invoke_without_newrelic(*args)
            end
  
            NewRelic::Agent::Instrumentation::RakeInstrumentation.before_invoke_transaction(self)
  
            NewRelic::Agent::Tracer.in_transaction(name: "OtherTransaction/Rake/invoke/#{name}", category: :rake) do
              NewRelic::Agent::Instrumentation::RakeInstrumentation.record_attributes(args, self)
              invoke_without_newrelic(*args)
            end
          end
        end

      end

    end
  end
end





