# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module LanguageSupport
    extend self

    @@forkable = nil
    def can_fork?
      # this is expensive to check, so we should only check once
      return @@forkable if !@@forkable.nil?

      @@forkable = Process.respond_to?(:fork)
    end

    def gc_profiler_usable?
      defined?(::GC::Profiler) && !jruby?
    end

    def gc_profiler_enabled?
      gc_profiler_usable? && ::GC::Profiler.enabled? && !::NewRelic::Agent.config[:disable_gc_profiler]
    end

    def object_space_usable?
      if jruby?
        require 'jruby'
        JRuby.runtime.is_object_space_enabled
      else
        defined?(::ObjectSpace)
      end
    end

    def jruby?
      RUBY_ENGINE == 'jruby'
    end

    def constantize(const_name)
      return if const_name.nil?

      Object.const_get(const_name)
    rescue NameError
    end

    def camelize(string)
      camelized = string.downcase
      camelized.split(/\-|\_/).map(&:capitalize).join
    end

    def camelize_with_first_letter_downcased(string)
      camelized = camelize(string)
      camelized[0].downcase.concat(camelized[1..-1])
    end

    def snakeize(string)
      string.gsub(/(.)([A-Z])/, '\1_\2').downcase
    end

    def bundled_gem?(gem_name)
      return false unless defined?(Bundler)

      NewRelic::Helper.rubygems_specs.map(&:name).include?(gem_name)
    rescue => e
      ::NewRelic::Agent.logger.info("Could not determine if third party #{gem_name} gem is installed", e)
      false
    end
  end
end
