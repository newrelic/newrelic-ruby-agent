# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :active_job

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
      adapter = ::ActiveJob::Base.queue_adapter.name
      queue   = job.queue_name

      trace_execution_scoped("MessageBroker/#{adapter}/Queue/Produce/Named/#{queue}") do
        block.call
      end
    end

  end
end
