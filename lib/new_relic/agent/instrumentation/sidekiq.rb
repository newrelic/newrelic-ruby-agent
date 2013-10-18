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

      def call(worker, msg, queue)
        perform_action_with_newrelic_trace(
          :name => 'perform',
          :class_name => msg['class'],
          :category => 'OtherTransaction/SidekiqJob') do

          if NewRelic::Agent.config[:'sidekiq.capture_params']
            NewRelic::Agent.add_custom_parameters(:job_arguments => msg['args'])
          end

          yield
        end
      end
    end

    Sidekiq.configure_server do |config|
      config.server_middleware do |chain|
        chain.add NewRelic::SidekiqInstrumentation
      end
    end
  end
end
