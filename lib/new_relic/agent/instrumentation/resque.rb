DependencyDetection.defer do
  @name = :resque
  
  depends_on do
    defined?(::Resque::Job) && !NewRelic::Agent.config[:disable_resque]  &&
      !NewRelic::LanguageSupport.using_version?('1.9.1')
  end

  executes do
    NewRelic::Agent.logger.debug 'Installing Resque instrumentation'
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
              perform_action_with_newrelic_trace(:name => 'perform',
                                   :class_name => self.name,
                                   :category => 'OtherTransaction/ResqueJob') do
                yield(*args)
              end
            ensure
              NewRelic::Agent.shutdown if NewRelic::LanguageSupport.can_fork?
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
        NewRelic::Agent.register_report_channel(job.object_id)
      end
      
      ::Resque.after_fork do |job|
        NewRelic::Agent.after_fork(:report_to_channel => job.object_id)
      end
    end
  end
end 

# call this now so it is memoized before potentially forking worker processes
NewRelic::LanguageSupport.can_fork?
