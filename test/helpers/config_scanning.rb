# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module TestHelpers
    module ConfigScanning
      # This is a bit loose (allows any config[] with the right key) so we can pass
      # NewRelic::Agent.config into classes as long as we call the variable config
      AGENT_CONFIG_PATTERN       = /config\[:['"]?([a-z\._]+)['"]?\s*\]/
      DEFAULT_VALUE_OF_PATTERN   = /:default\s*=>\s*value_of\(:['"]?([a-z\._]+)['"]?\)\s*/
      REGISTER_CALLBACK_PATTERN  = /register_callback\(:['"]?([a-z\._]+)['"]?\)/
      NAMED_DEPENDENCY_PATTERN   = /^\s*named[ (]+\:?([a-z0-9\._]+).*$/
      EVENT_BUFFER_MACRO_PATTERN = /(capacity_key|enabled_key)\s+:['"]?([a-z\._]+)['"]?/

      def scan_and_remove_used_entries default_keys, non_test_files
        non_test_files.each do |file|
          lines_in(file).each do |line|
            captures = []
            captures << line.scan(AGENT_CONFIG_PATTERN)
            captures << line.scan(DEFAULT_VALUE_OF_PATTERN)
            captures << line.scan(REGISTER_CALLBACK_PATTERN)
            captures << line.scan(EVENT_BUFFER_MACRO_PATTERN)
            captures << line.scan(NAMED_DEPENDENCY_PATTERN).map(&method(:disable_name))

            captures.flatten.map do |key|
              default_keys.delete key.gsub("'", "").to_sym
            end

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
