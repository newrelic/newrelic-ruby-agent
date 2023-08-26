# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module TestHelpers
    module ConfigScanning
      # This is a bit loose (allows any config[] with the right key) so we can pass
      # NewRelic::Agent.config into classes as long as we call the variable config
      AGENT_CONFIG_PATTERN = /config\[:(['"])?([a-z\._]+)\1?\s*\]/
      DEFAULT_VALUE_OF_PATTERN = /:default\s*=>\s*value_of\(:(['"])?([a-z\._]+)\1?\)\s*/
      DEFAULT_INST_VALUE_OF_PATTERN = /:default\s*=>\s*instrumentation_value_of\(:(['"])?([a-z._]+)\1?\)|\(:(['"])?([a-z._]+)\3?\s*,\s*:(['"])?([a-z._]+)\5?\)/
      REGISTER_CALLBACK_PATTERN = /register_callback\(:(['"])?([a-z\._]+)\1?\)/
      NAMED_DEPENDENCY_PATTERN = /^\s*named[ (]+\:?([a-z0-9\._]+).*$/
      EVENT_BUFFER_MACRO_PATTERN = /(capacity_key|enabled_key)\s+:(['"])?([a-z\._]+)\2?/
      ASSIGNED_CONSTANT_PATTERN = /[A-Z]+\s*=\s*:(['"])?([a-z\._]+)\1?\s*/

      # These config settings shouldn't be worried about, possibly because they
      # are only referenced via Ruby metaprogramming that won't work with this
      # module's regex matching
      IGNORED = %i[sidekiq.args.include sidekiq.args.exclude]

      def scan_and_remove_used_entries(default_keys, non_test_files)
        non_test_files.each do |file|
          lines_in(file).each do |line|
            captures = []
            captures << line.scan(AGENT_CONFIG_PATTERN)
            captures << line.scan(DEFAULT_VALUE_OF_PATTERN)
            captures << line.scan(DEFAULT_INST_VALUE_OF_PATTERN)
            captures << line.scan(REGISTER_CALLBACK_PATTERN)
            captures << line.scan(EVENT_BUFFER_MACRO_PATTERN)
            captures << line.scan(ASSIGNED_CONSTANT_PATTERN)
            captures << line.scan(NAMED_DEPENDENCY_PATTERN).map(&method(:disable_name))

            captures.flatten.compact.each do |key|
              default_keys.delete(key.delete("'").to_sym)
            end

            IGNORED.each { |key| default_keys.delete(key) }

            # Remove any config keys that are annotated with the 'dynamic_name' setting
            # This indicates that the names of these keys are constructed dynamically at
            # runtime, so we don't expect any explicit references to them in code.
            default_keys.delete_if do |key_name|
              NewRelic::Agent::Configuration::DEFAULTS[key_name][:dynamic_name]
            end
          end
        end
      end

      private

      def disable_name(names)
        names.map { |name| "disable_#{name}" }
      end

      def lines_in(file)
        File.read(file).split("\n")
      end
    end
  end
end
