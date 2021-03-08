# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic::Agent::Instrumentation
  module Rake
    module Prepend 
      def invoke(*args)
        unless NewRelic::Agent::Instrumentation::RakeInstrumentation.should_trace? name
          return super
        end

        begin
          timeout = NewRelic::Agent.config[:'rake.connect_timeout']
          NewRelic::Agent.instance.wait_on_connect(timeout)
        rescue => e
          NewRelic::Agent.logger.error("Exception in wait_on_connect", e)
          return super
        end

        NewRelic::Agent::Instrumentation::RakeInstrumentation.before_invoke_transaction(self)

        NewRelic::Agent::Tracer.in_transaction(name: "OtherTransaction/Rake/invoke/#{name}", category: :rake) do
          NewRelic::Agent::Instrumentation::RakeInstrumentation.record_attributes(args, self)
          super
        end
      end
    end
  end
end
