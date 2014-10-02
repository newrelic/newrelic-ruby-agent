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

    ::ActiveJob::Base.around_enqueue do |job, block|
      ::NewRelic::Agent::Instrumentation::ActiveJobHelper.enqueue(job, block)
    end

    ::ActiveJob::Base.around_perform do |job, block|
      ::NewRelic::Agent::Instrumentation::ActiveJobHelper.perform(job, block)
    end
  end
end

module NewRelic
  module Agent
    module Instrumentation
      module ActiveJobHelper
        include ::NewRelic::Agent::MethodTracer

        def self.enqueue(job, block)
          run_in_trace(job, block, :Produce)
        end

        def self.perform(job, block)
          state = ::NewRelic::Agent::TransactionState.tl_get

          # Don't nest transactions if we're already in a web transaction.
          # Probably inline processing the job if that happens, so just trace.
          if state.in_web_transaction?
            run_in_trace(job, block, :Consume)
          else
            run_in_transaction(state, job, block)
          end
        end

        def self.run_in_trace(job, block, event)
          trace_execution_scoped("MessageBroker/#{adapter}/Queue/#{event}/Named/#{job.queue_name}") do
            block.call
          end
        end

        def self.run_in_transaction(state, job, block)
          begin
            name = "OtherTransaction/#{adapter}/#{job.class}/perform"
            ::NewRelic::Agent::Transaction.start(state, :other, :transaction_name => name)
            block.call
          ensure
            ::NewRelic::Agent::Transaction.stop(state)
          end
        end

        ADAPTER_REGEX = /ActiveJob::QueueAdapters::(.*)Adapter/

        def self.adapter
          clean_adapter_name(::ActiveJob::Base.queue_adapter.name)
        end

        def self.clean_adapter_name(name)
          name = "ActiveJob::#{$1}" if ADAPTER_REGEX =~ name
          name
        end
      end
    end
  end
end
