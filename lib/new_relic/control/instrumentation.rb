module NewRelic
  class Control
    module Instrumentation
      def load_instrumentation_files pattern
        Dir.glob(pattern) do |file|
          begin
            log.debug "Processing instrumentation file '#{file}'"
            require file.to_s
          rescue => e
            log.error "Error loading instrumentation file '#{file}': #{e}"
            log.debug e.backtrace.join("\n")
          end
        end
      end

      # Install stubs to the proper location so the app code will not fail
      # if the agent is not running.
      def install_shim
        # Once we install instrumentation, you can't undo that by installing the shim.
        raise "Cannot install the Agent shim after instrumentation has already been installed!" if @instrumented
        NewRelic::Agent.agent = NewRelic::Agent::ShimAgent.instance
      end

      # Add instrumentation.  Don't call this directly.  Use NewRelic::Agent#add_instrumentation.
      # This will load the file synchronously if we've already loaded the default
      # instrumentation.
      #
      def add_instrumentation pattern
        if @instrumented
          load_instrumentation_files pattern
        else
          @instrumentation_files << pattern
        end
      end

      def _delayed_instrumentation
        Rails.configuration.after_initialize do
          _install_instrumentation
        end
      rescue
        _install_instrumentation
      end

      def install_instrumentation
        if defined?(Rails) && !Rails.initialized?
          _delayed_instrumentation
        else
          _install_instrumentation
        end
      rescue NameError
        # needed in the rails 3 case, where Rails.initialized? raises
        # an error if rails has not been initialised. which is totally sane.
        _delayed_instrumentation
      end

      def load_samplers
        agent = NewRelic::Agent.instance
        NewRelic::Agent::Sampler.sampler_classes.each do | subclass |
          begin
            log.debug "#{subclass.name} not supported on this platform." and next if not subclass.supported_on_this_platform?
            sampler = subclass.new
            if subclass.use_harvest_sampler?
              agent.stats_engine.add_harvest_sampler sampler
              log.debug "Registered #{subclass.name} for harvest time sampling"
            else
              agent.stats_engine.add_sampler sampler
              log.debug "Registered #{subclass.name} for periodic sampling"
            end
          rescue NewRelic::Agent::Sampler::Unsupported => e
            log.info "#{subclass} sampler not available: #{e}"
          rescue => e
            log.error "Error registering sampler: #{e}, #{e.backtrace.join("\n")}"
          end
        end
      end

      private

      def _install_instrumentation
        return if @instrumented

        @instrumented = true

        # Instrumentation for the key code points inside rails for monitoring by NewRelic.
        # note this file is loaded only if the newrelic agent is enabled (through config/newrelic.yml)
        instrumentation_path = File.expand_path(File.join(File.dirname(__FILE__), '..', 'agent','instrumentation'))
        @instrumentation_files <<
        File.join(instrumentation_path, '*.rb') <<
        File.join(instrumentation_path, app.to_s, '*.rb')
        @instrumentation_files.each { | pattern |  load_instrumentation_files pattern }
        log.debug "Finished instrumentation"
      end
    end
  end
end
