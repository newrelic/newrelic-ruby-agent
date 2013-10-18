# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  @name = :resque

  depends_on do
    defined?(::Resque::Job) && !NewRelic::Agent.config[:disable_resque]  &&
      !NewRelic::LanguageSupport.using_version?('1.9.1')
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Resque instrumentation'
  end

  executes do
    # == Resque Instrumentation
    #
    # Installs a hook to ensure the agent starts manually when the worker
    # starts and also adds the tracer to the process method which executes
    # in the forked task.

    module Resque
      module Plugins
        module NewRelicInstrumentation
          include NewRelic::Agent::Instrumentation::ControllerInstrumentation

          def around_perform_with_monitoring(*args)
            begin
              perform_action_with_newrelic_trace(
                :name => 'perform',
                :class_name => self.name,
                :category => 'OtherTransaction/ResqueJob') do

                if NewRelic::Agent.config[:'resque.capture_params']
                  NewRelic::Agent.add_custom_parameters(:job_arguments => args)
                end

                yield(*args)
              end
            ensure
              NewRelic::Agent.shutdown if NewRelic::LanguageSupport.can_fork? &&
                                          (!Resque.respond_to?(:inline) || !Resque.inline)
            end
          end
        end
      end
    end

    module NewRelic
      module Agent
        module Instrumentation
          module ResqueInstrumentationInstaller
            def payload_class
              klass = super
              klass.instance_eval do
                extend ::Resque::Plugins::NewRelicInstrumentation
              end
            end
          end
        end
      end
    end

    ::Resque::Job.class_eval do
      def self.new(*args)
        super(*args).extend NewRelic::Agent::Instrumentation::ResqueInstrumentationInstaller
      end
    end

    if NewRelic::LanguageSupport.can_fork?
      # Resque::Worker#fork isn't around in Resque 2.x
      if NewRelic::VersionNumber.new(::Resque::VERSION) < NewRelic::VersionNumber.new("2.0.0")
        ::Resque::Worker.class_eval do
          if NewRelic::Agent.config[:'resque.use_harvest_lock']
            ::NewRelic::Agent.logger.info 'Installing Resque harvest/fork synchronization'
            def fork_with_newrelic(*args, &block)
              NewRelic::Agent.instance.synchronize_with_harvest do
                fork_without_newrelic(*args, &block)

                # Reached in parent, not expected in the child since Resque
                # uses the block form of fork
              end
            end

            alias_method :fork_without_newrelic, :fork
            alias_method :fork, :fork_with_newrelic
          end
        end
      end

      ::Resque.before_first_fork do
        NewRelic::Agent.manual_start(:dispatcher   => :resque,
                                     :sync_startup => true,
                                     :start_channel_listener => true)
      end

      ::Resque.before_fork do |job|
        NewRelic::Agent.register_report_channel(job.object_id)
      end

      ::Resque.after_fork do |job|
        # Only suppress reporting Instance/Busy for forked children
        # Traced errors UI relies on having the parent process report that metric
        NewRelic::Agent.after_fork(:report_to_channel => job.object_id,
                                   :report_instance_busy => false)
      end
    end
  end
end

# call this now so it is memoized before potentially forking worker processes
NewRelic::LanguageSupport.can_fork?
