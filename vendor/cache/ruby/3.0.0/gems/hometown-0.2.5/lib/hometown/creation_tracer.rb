module Hometown
  class CreationTracer
    def initialize
      @tracing_classes = {}
    end

    def patch(clazz, other_instance_hook=nil)
      if !patched?(clazz)
        remember_patched(clazz)
        on_creation_add_trace_for_instance(clazz)
        install_traced_new(clazz)
      end

      # Critical that we only add other instance hooks after our primary
      # creation hook is registered above!
      update_on_instance_created(clazz, other_instance_hook)
    end

    def patched?(clazz)
      @tracing_classes.include?(clazz)
    end

    def remember_patched(clazz)
      @tracing_classes[clazz] = true
    end

    def on_creation_add_trace_for_instance(clazz)
      update_on_instance_created(clazz, method(:add_trace_for))
    end

    def install_traced_new(clazz)
      clazz.instance_eval do
        class << self
          def new_traced(*args, &blk)
            instance = new_untraced(*args, &blk)
            self.instance_hooks.each { |hook| hook.call(instance) }
            instance
          end

          alias_method :new_untraced, :new
          alias_method :new, :new_traced
        end
      end
    end

    HOMETOWN_TRACE_ON_INSTANCE = :@__hometown_creation_backtrace

    def add_trace_for(instance)
      trace = Hometown::Trace.new(instance.class, scrubbed_caller)
      instance.instance_variable_set(HOMETOWN_TRACE_ON_INSTANCE, trace)
    end

    def scrubbed_caller
      backtrace = caller.dup
      backtrace.reject { |line| %r{/lib/hometown/creation_tracer.rb}.match(line) }
    end

    def find_trace_for(instance)
      instance.instance_variable_get(HOMETOWN_TRACE_ON_INSTANCE)
    end

    # This hook allows other tracing in Hometown to get a whack at an object
    # after it's been created without forcing them to patch new themselves
    def update_on_instance_created(clazz, on_instance_created)
      return unless on_instance_created
      clazz.instance_eval do
        def instance_hooks
          hooks = (self.ancestors + [self]).map do |target|
            target.instance_variable_get(:@instance_hooks)
          end

          hooks.flatten!
          hooks.compact!
          hooks.uniq!
          hooks
        end

        @instance_hooks ||= []
        @instance_hooks << on_instance_created
      end
    end
  end
end
