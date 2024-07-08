# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'yaml'
require_relative 'helpers/version_bump'

# gha = GitHub Actions
namespace :gha do
  # See .github/versions.yml
  desc 'Update 3rd party action versions across all workflows'
  task :update_versions do
    gh_dir = File.expand_path('../../../.github', __FILE__)
    info = YAML.load_file(File.join(gh_dir, 'versions.yml'))
    workflows = Dir.glob(File.join(gh_dir, 'workflows', '*.yml'))
    workflows.each do |workflow|
      original = File.read(workflow)
      modified = original.dup
      info.each do |action, settings|
        modified.gsub!(/uses: #{action}.*$/, "uses: #{action}@#{settings[:sha]} # tag #{settings[:tag]}")
      end

      if original != modified
        File.open(workflow, 'w') { |f| f.puts modified }
        puts "Updated #{workflow} with changes"
      else
        puts "#{workflow} remains unchanged"
      end
    end
  end
end
