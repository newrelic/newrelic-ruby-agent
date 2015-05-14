# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  @name = :sidekiq

  depends_on do
    defined?(::Sidekiq) && !NewRelic::Agent.config[:disable_sidekiq]
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Sidekiq instrumentation'
  end

  executes do
    class NewRelic::SidekiqInstrumentation
      include NewRelic::Agent::Instrumentation::ControllerInstrumentation

      # Client middleware has additional parameters, and our tests use the
      # middleware client-side to work inline.
      def call(worker, msg, queue, *_)
        trace_args = if worker.respond_to?(:newrelic_trace_args)
          worker.newrelic_trace_args(msg, queue)
        else
          self.class.default_trace_args(msg)
        end

        perform_action_with_newrelic_trace(trace_args) do
          NewRelic::Agent::Transaction.merge_untrusted_agent_attributes(msg['args'], :'job.sidekiq.args',
            NewRelic::Agent::AttributeFilter::DST_NONE)

          yield
        end
      end

      def self.default_trace_args(msg)
        {
          :name => 'perform',
          :class_name => msg['class'],
          :category => 'OtherTransaction/SidekiqJob'
        }
      end
    end

    class Sidekiq::Extensions::DelayedClass
      def newrelic_trace_args(msg, queue)
        (target, method_name, _args) = YAML.load(msg['args'][0])
        {
          :name => method_name,
          :class_name => target.name,
          :category => 'OtherTransaction/SidekiqJob'
        }
      rescue => e
        NewRelic::Agent.logger.error("Failure during deserializing YAML for Sidekiq::Extensions::DelayedClass", e)
        NewRelic::SidekiqInstrumentation.default_trace_args(msg)
      end
    end

    Sidekiq.configure_server do |config|
      config.server_middleware do |chain|
        chain.add NewRelic::SidekiqInstrumentation
      end

      if config.respond_to?(:error_handlers)
        config.error_handlers << Proc.new do |error, *_|
          NewRelic::Agent.notice_error(error)
        end
      end
    end
  end
end
