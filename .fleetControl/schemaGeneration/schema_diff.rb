#!/usr/bin/env ruby
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'json'

# Classifies the difference between two generated config schemas and turns that
# into a semantic-version bump for the Fleet Control config schema.
#
# The schema uses flat dotted keys with no `required` array and a fixed
# `additionalProperties: true` at the root, so only the change kinds that shape
# can actually produce are classified. If the generator ever starts emitting a
# `required` array, nested objects, or `additionalProperties: false`, add the
# matching rules here — otherwise those changes would be silently under-bumped.
module SchemaDiff
  # Change kinds grouped by the bump they force. Most severe wins.
  BREAKING = %w[property_removed type_changed enum_introduced enum_value_removed].freeze
  ADDITIVE = %w[property_added enum_removed_entirely enum_value_added default_changed].freeze
  COSMETIC = %w[description_changed].freeze

  NO_DEFAULT = Object.new # sentinel so an absent default is distinct from a nil default

  module_function

  # Parse a schema JSON file into a Hash. Missing or malformed files yield {}
  # so a bootstrap run (no baseline schema yet) is handled by the caller.
  def load_existing(path)
    return {} unless File.exist?(path)

    JSON.parse(File.read(path))
  rescue JSON::ParserError
    {}
  end

  # Decide the version bump from the previous release's schema. `baseline` is
  # the previous release's parsed schema (nil/empty means there was no schema at
  # the last release — treat this as the first one, no bump). `starter_version`
  # is the schema version at that release, which the bump is applied to (so a
  # re-run against the same release is idempotent). Returns
  # { action:, bump:, old_version:, new_version:, changes: }.
  #
  # Actions: :first_release (no prior schema), :no_change (unchanged since the
  #          last release), :bump (a version bump is recommended).
  def bump(baseline:, current:, starter_version:)
    # No prior schema, or no version to bump from -> treat as the first release.
    return {action: :first_release, bump: 'none', changes: []} if baseline.nil? || baseline.empty? || starter_version.to_s.empty?

    changes = classify_changes(baseline, current)
    kind = recommend_bump(changes)
    return {action: :no_change, bump: 'none', changes: changes} if kind == 'none'

    {action: :bump, bump: kind, old_version: starter_version,
     new_version: apply_bump(starter_version, kind), changes: changes}
  end

  # Compare two schemas' property maps and return a list of change records:
  # { path:, kind:, severity:, detail: }.
  def classify_changes(old_schema, new_schema)
    old_props = old_schema['properties'] || {}
    new_props = new_schema['properties'] || {}
    changes = []

    (old_props.keys | new_props.keys).sort.each do |key|
      if !old_props.key?(key)
        changes << change(key, 'property_added', 'new property')
      elsif !new_props.key?(key)
        changes << change(key, 'property_removed', 'property removed')
      else
        changes.concat(classify_leaf(old_props[key], new_props[key], key))
      end
    end

    changes
  end

  # Classify the changes within a single property (type, enum, default,
  # description). Returns an array; a property can change in more than one way.
  def classify_leaf(old_prop, new_prop, path)
    changes = []
    changes.concat(type_changes(old_prop, new_prop, path))
    changes.concat(enum_changes(old_prop, new_prop, path))
    changes.concat(default_changes(old_prop, new_prop, path))
    changes.concat(description_changes(old_prop, new_prop, path))
    changes
  end

  # Highest-severity bump implied by the changes.
  def recommend_bump(changes)
    severities = changes.map { |c| c[:severity] }
    return 'major' if severities.include?('breaking')
    return 'minor' if severities.include?('additive')
    return 'patch' if severities.include?('cosmetic')

    'none'
  end

  # Apply a bump kind to a semver string (X.Y.Z). 'none' returns it unchanged.
  def apply_bump(version, bump)
    return version if bump == 'none'

    major, minor, patch = parse_semver(version)
    case bump
    when 'major' then "#{major + 1}.0.0"
    when 'minor' then "#{major}.#{minor + 1}.0"
    when 'patch' then "#{major}.#{minor}.#{patch + 1}"
    else raise ArgumentError, "unknown bump kind: #{bump.inspect}"
    end
  end

  # Replace the single `version:` line in configurationDefinitions.yml text.
  # Raises unless exactly one such line exists, so a malformed file can't be
  # silently half-updated.
  def bump_version_line(yaml_text, new_version)
    pattern = /^(\s*version:\s*)(\S+)(\s*)$/
    matches = yaml_text.scan(pattern).size
    raise "expected exactly 1 'version:' line, found #{matches}" unless matches == 1

    yaml_text.sub(pattern) { "#{Regexp.last_match(1)}#{new_version}#{Regexp.last_match(3)}" }
  end

  # One-line human rendering: + added, - removed, ~ modified.
  def render_change(change)
    symbol = case change[:kind]
    when 'property_added' then '+'
    when 'property_removed' then '-'
    else '~'
    end

    "#{symbol} #{change[:path]}: #{change[:detail]}"
  end

  # --- internals --------------------------------------------------------------

  def change(path, kind, detail)
    {path: path, kind: kind, severity: severity_for(kind), detail: detail}
  end

  def severity_for(kind)
    return 'breaking' if BREAKING.include?(kind)
    return 'additive' if ADDITIVE.include?(kind)
    return 'cosmetic' if COSMETIC.include?(kind)

    raise ArgumentError, "unclassified change kind: #{kind.inspect}"
  end

  # The type aspect of a property: its `anyOf` shape if present, else its `type`.
  def type_signature(prop)
    prop['anyOf'] || prop['type']
  end

  def type_changes(old_prop, new_prop, path)
    old_sig = type_signature(old_prop)
    new_sig = type_signature(new_prop)
    return [] if old_sig == new_sig

    [change(path, 'type_changed', "#{describe_type(old_sig)} -> #{describe_type(new_sig)}")]
  end

  def describe_type(signature)
    signature.is_a?(String) ? signature : 'array-or-string'
  end

  def enum_changes(old_prop, new_prop, path)
    old_enum = old_prop['enum']
    new_enum = new_prop['enum']
    return [] if old_enum == new_enum
    return [change(path, 'enum_introduced', "enum added: #{new_enum.join(', ')}")] if old_enum.nil?
    return [change(path, 'enum_removed_entirely', 'enum constraint removed')] if new_enum.nil?

    changes = []
    removed = old_enum - new_enum
    added = new_enum - old_enum
    changes << change(path, 'enum_value_removed', "enum values removed: #{removed.join(', ')}") unless removed.empty?
    changes << change(path, 'enum_value_added', "enum values added: #{added.join(', ')}") unless added.empty?
    changes
  end

  def default_changes(old_prop, new_prop, path)
    old_default = old_prop.key?('default') ? old_prop['default'] : NO_DEFAULT
    new_default = new_prop.key?('default') ? new_prop['default'] : NO_DEFAULT
    return [] if old_default == new_default

    [change(path, 'default_changed', "default changed: #{old_default.inspect} -> #{new_default.inspect}")]
  end

  def description_changes(old_prop, new_prop, path)
    return [] if old_prop['description'] == new_prop['description']

    [change(path, 'description_changed', 'description changed')]
  end

  def parse_semver(version)
    match = /\A(\d+)\.(\d+)\.(\d+)\z/.match(version.to_s)
    raise ArgumentError, "not a semver version: #{version.inspect}" unless match

    match.captures.map(&:to_i)
  end
end
