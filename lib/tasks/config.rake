# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'helpers/format'

namespace :newrelic do
  namespace :config do
    desc 'Write every public configuration setting into ruby-agent-configuration.mdx'
    task :docs => [] do
      Format.write_text_file
    end

    desc 'Write the configuration pages for the docs website into config-docs/'
    task :docs_pages => [] do
      Format.write_docs_pages
    end

    desc 'Generate the Fleet Control JSON Schema for agent configuration'
    task :schema => [] do
      require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '.fleetControl', 'schemaGeneration', 'generate_schema.rb'))
      GenerateSchema.run
    end

    desc 'Bump the config schema version from changes since the last release (pass [write] to apply; dry-run otherwise)'
    task :'schema:bump', [:mode] => [] do |t, args|
      require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '.fleetControl', 'schemaGeneration', 'bump_schema_version.rb'))
      BumpSchemaVersion.run(write: args[:mode] == 'write')
    end
  end
end
