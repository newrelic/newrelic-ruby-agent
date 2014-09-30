# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :activejob

  depends_on do
    defined?(::ActiveJob::Base)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing ActiveJob instrumentation'
  end

  executes do
    class ::ActiveJob::Base
      include ::NewRelic::Agent::MethodTracer
    end

    ::ActiveJob::Base.around_enqueue do |job, block|
      ::NewRelic::Agent::Instrumentation::ActiveJobHelper.trace(job, block, :Produce)
    end

    ::ActiveJob::Base.around_perform do |job, block|
      ::NewRelic::Agent::Instrumentation::ActiveJobHelper.trace(job, block, :Consume)
    end

  end
end

module NewRelic
  module Agent
    module Instrumentation
      module ActiveJobHelper
        def self.trace(job, block, event)
          adapter = clean_adapter_name(::ActiveJob::Base.queue_adapter.name)
          queue   = job.queue_name
          trace_execution_scoped("MessageBroker/#{adapter}/Queue/#{event}/Named/#{queue}") do
            block.call
          end
        end

        ADAPTER_REGEX = /ActiveJob::QueueAdapters::(.*)Adapter/

        def self.clean_adapter_name(name)
          name = "ActiveJob::#{$1}" if ADAPTER_REGEX =~ name
          name
        end
      end
    end
  end
end
