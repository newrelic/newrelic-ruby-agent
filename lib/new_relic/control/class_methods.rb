module NewRelic
  class Control
    module ClassMethods
      # Access the Control singleton, lazy initialized
      def instance
        @instance ||= new_instance
      end
      
      def mark_browser_request
        Thread::current[:browser_request] = true
      end
      

      # Create the concrete class for environment specific behavior:
      def new_instance
        @local_env = NewRelic::LocalEnvironment.new
        if @local_env.framework == :test
          config = File.expand_path("../../../../test/config/newrelic.yml", __FILE__)
          require "config/test_control"
          NewRelic::Control::Frameworks::Test.new @local_env, config
        else
          begin
            require "new_relic/control/frameworks/#{@local_env.framework}.rb"
          rescue LoadError
          end
          klass = NewRelic::Control::Frameworks.const_get(@local_env.framework.to_s.capitalize)
          klass.new @local_env
        end
      end

      # The root directory for the plugin or gem
      def newrelic_root
        File.expand_path("../../../..", __FILE__)
      end
    end
    extend ClassMethods
  end
end

