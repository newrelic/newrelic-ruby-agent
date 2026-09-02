#!/usr/bin/env ruby
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'json'
require_relative 'schema_diff'

# Driver for the config schema version bump: diffs the current schema against
# the previous release's schema (read from the latest release tag) and, on
# --write, updates the version in configurationDefinitions.yml. The change
# classification lives in SchemaDiff; this file is the git + file-I/O glue.
#
# Run it: `ruby bump_schema_version.rb`          # dry-run (reports)
#         `ruby bump_schema_version.rb --write`  # apply the bump
module BumpSchemaVersion
  FLEET_CONTROL_DIR = File.expand_path('..', __dir__)
  SCHEMA_PATH = File.join(FLEET_CONTROL_DIR, 'schemas', 'config.json')
  CONFIG_DEF_PATH = File.join(FLEET_CONTROL_DIR, 'configurationDefinitions.yml')
  SCHEMA_REPO_PATH = '.fleetControl/schemas/config.json'
  CONFIG_DEF_REPO_PATH = '.fleetControl/configurationDefinitions.yml'

  module_function

  # Full run: read the previous release from git, decide, write, and report.
  def run(write: false, schema_path: SCHEMA_PATH, config_def_path: CONFIG_DEF_PATH)
    tag, baseline, starter_version = previous_release
    current = SchemaDiff.load_existing(schema_path)
    result = apply(baseline: baseline, current: current, starter_version: starter_version,
      config_def_path: config_def_path, write: write)
    report(result, tag, write)
    result
  end

  # Decide (via SchemaDiff) and, when write: true and a bump is due, rewrite the
  # version line. Pure of git, so it can be exercised with fixtures. Returns the
  # SchemaDiff.bump result Hash.
  def apply(baseline:, current:, starter_version:, config_def_path:, write:)
    result = SchemaDiff.bump(baseline: baseline, current: current, starter_version: starter_version)
    return result unless write && result[:action] == :bump

    text = File.read(config_def_path)
    if text[/^\s*version:\s*(\S+)/, 1] != result[:new_version]
      File.write(config_def_path, SchemaDiff.bump_version_line(text, result[:new_version]))
    end
    result
  end

  # [tag, baseline_schema_or_nil, starter_version_or_nil] for the latest release.
  def previous_release
    tag = latest_release_tag
    return [nil, nil, nil] unless tag

    schema_text = git_show(tag, SCHEMA_REPO_PATH)
    defs_text = git_show(tag, CONFIG_DEF_REPO_PATH)
    baseline = schema_text ? JSON.parse(schema_text) : nil
    [tag, baseline, defs_text && defs_text[/^\s*version:\s*(\S+)/, 1]]
  end

  # Latest final release tag (bare X.Y.Z, ignoring -pre prereleases), or nil.
  def latest_release_tag
    `git tag --list --sort=-v:refname`.split("\n").map(&:strip).find { |name| name.match?(/\A\d+\.\d+\.\d+\z/) }
  end

  def git_show(ref, path)
    out = `git show #{ref}:#{path} 2>/dev/null`
    out.empty? ? nil : out
  end

  def report(result, tag, write)
    (result[:changes] || []).each { |c| puts "  #{SchemaDiff.render_change(c)}" }

    case result[:action]
    when :first_release
      puts 'No schema at the last release (or no release tag); treating this as the first. No bump.'
    when :no_change
      puts "Schema unchanged since #{tag}; no version bump."
    when :bump
      puts(if write
        "Bumped schema version: #{result[:old_version]} -> #{result[:new_version]}."
      else
        "Recommended bump: #{result[:bump]} (#{result[:old_version]} -> #{result[:new_version]}). Dry-run; pass --write to apply."
      end)
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  begin
    BumpSchemaVersion.run(write: ARGV.include?('--write'))
  rescue StandardError => e
    warn "Schema bump failed: #{e.class}: #{e.message}"
    exit 2
  end
end
