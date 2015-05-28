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
    if NewRelic::Agent.config[:'resque.use_ruby_dns'] && NewRelic::Agent.config[:dispatcher] == :resque
      ::NewRelic::Agent.logger.info 'Requiring resolv-replace'
      require 'resolv'
      require 'resolv-replace'
    end
  end

  executes do
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

                NewRelic::Agent::Transaction.merge_untrusted_agent_attributes(args, :'job.resque.args',
                  NewRelic::Agent::AttributeFilter::DST_NONE)

                yield(*args)
              end
            ensure
              NewRelic::Agent.agent.flush_pipe_data
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
      ::Resque.before_first_fork do
        NewRelic::Agent.manual_start(:dispatcher   => :resque,
                                     :sync_startup => true,
                                     :start_channel_listener => true)
      end

      ::Resque.before_fork do |job|
        if ENV['FORK_PER_JOB'] != 'false'
          NewRelic::Agent.register_report_channel(job.object_id)
        end
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
