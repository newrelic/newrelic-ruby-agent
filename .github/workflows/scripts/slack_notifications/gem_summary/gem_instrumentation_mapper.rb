# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'yaml'

module GemSummary
  class GemInstrumentationMapper
    INSTRUMENTATION_FILES = %w[instrumentation.rb prepend.rb].freeze
    INSTRUMENTATION_BASE_PATH = File.expand_path('../../../../../lib/new_relic/agent/instrumentation', __dir__)
    GEM_TO_INSTRUMENTATION = YAML.safe_load_file(File.expand_path('gem_instrumentation.yml', __dir__)).freeze

    def self.instrumentation_summary(gem_name)
      value = GEM_TO_INSTRUMENTATION[gem_name]
      return nil if value.nil?

      files = value.is_a?(Array) ? value : INSTRUMENTATION_FILES.map { |filename| "#{value}/#{filename }" }

      snippets = files.filter_map do |file|
        path = File.join(INSTRUMENTATION_BASE_PATH, file)
        unless File.exist?(path)
          puts "Warning: instrumentation file not found at #{path} (referenced by gem_instrumentation.yml)"
          next
        end

        "# === #{file} ===\n#{File.read(path)}"
      end

      snippets.empty? ? nil : snippets.join("\n\n")
    end
  end
end
