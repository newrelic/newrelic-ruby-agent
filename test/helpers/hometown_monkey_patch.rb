# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Hometown
  class CreationTracer
    def find_trace_for(instance)
      return unless instance.instance_variable_defined?(HOMETOWN_TRACE_ON_INSTANCE)
      instance.instance_variable_get(HOMETOWN_TRACE_ON_INSTANCE)
    end

    # This hook allows other tracing in Hometown to get a whack at an object
    # after it's been created without forcing them to patch new themselves
    def update_on_instance_created(clazz, on_instance_created)
      return unless on_instance_created
      clazz.instance_eval do
        def instance_hooks
          hooks = (self.ancestors + [self]).map do |target|
            if target.instance_variable_defined?(:@instance_hooks)
              target.instance_variable_get(:@instance_hooks)
            end
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
