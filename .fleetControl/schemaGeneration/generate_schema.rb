#!/usr/bin/env ruby
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'json'
require 'fileutils'
# Optional: used to validate the generated schema against the Draft 2020-12
# meta-schema before writing. Absent on the old-Ruby CI job (gated out of the
# gemspec), where validation soft-skips rather than failing.
begin
  require 'json_schemer'
rescue LoadError
  nil
end
require_relative '../../lib/new_relic/agent/configuration/default_source'
# Reused for description cleanup so the schema, the config docs, and the
# generated newrelic.yml all strip markdown the same way (no drift).
require_relative '../../lib/tasks/helpers/newrelicyml'
# Reused for INSTRUMENTATION_STANDARD_VALUES so the schema can't drift from
# the values the agent's dependency-detection framework actually accepts.
require_relative '../../lib/new_relic/dependency_detection'

# Generates a JSON Schema (Draft 2020-12) describing the New Relic Ruby agent's
# configuration, read straight from NewRelic::Agent::Configuration::DEFAULTS.
# The output (../schemas/config.json) is what Fleet Control consumes to
# validate and render agent configuration.
#
# Run it: `ruby .fleetControl/schemaGeneration/generate_schema.rb`
module GenerateSchema
  DEFAULTS = NewRelic::Agent::Configuration::DEFAULTS
  SCHEMA_URI = 'https://json-schema.org/draft/2020-12/schema'
  OUTPUT_PATH = File.expand_path('../schemas/config.json', __dir__)
  Boolean = NewRelic::Agent::Configuration::Boolean

  # Public settings that aren't configurable via newrelic.yml (env-only, read
  # before the YAML loads). Reuse the existing authoritative list so this
  # generator and the newrelic.yml generator can't drift.
  EXCLUDE_KEYS = NewRelicYML::SKIP

  # The agent accepts Array-typed settings as either a real YAML array or a
  # single delimited string (a :transform splits it), so the schema allows both.
  ARRAY_OR_STRING = {
    'anyOf' => [
      {'type' => 'array', 'items' => {'type' => 'string'}},
      {'type' => 'string'}
    ]
  }.freeze

  # Enum values for settings that are effectively enums but carry no :allowlist
  # in DEFAULTS. Values are verified against the code that consumes each setting,
  # NOT the prose descriptions (which omit log_level's `fatal` and mislabel
  # `to_app`):
  #   - log_level:  agent_logger.rb LOG_LEVELS
  #   - record_sql: database.rb#record_sql_method
  #
  # LONG-TERM FIX: these maps are a second source of truth that can drift from
  # the code. The better fix is to add an :allowlist to each of these settings
  # in default_source.rb. The generator already turns :allowlist into an enum
  # automatically (see build_property), and the agent enforces :allowlist at
  # runtime (manager.rb#enforce_allowlist) — so doing that gives real runtime
  # validation these settings currently lack AND lets these override maps be
  # deleted entirely.
  BASE_ENUM_OVERRIDES = {
    'log_level' => %w[debug info warn error fatal],
    'transaction_tracer.record_sql' => %w[off none raw obfuscated],
    'slow_sql.record_sql' => %w[off none raw obfuscated]
  }.freeze

  # instrumentation.* toggles. Most accept the standard set, reused directly
  # from dependency_detection.rb so it can't drift; a few are simple on/off.
  INSTRUMENTATION_STANDARD_VALUES = DependencyDetection::Dependent::VALID_CONFIG_VALUES.map(&:to_s).freeze
  INSTRUMENTATION_ONOFF_VALUES = %w[enabled disabled].freeze
  INSTRUMENTATION_ONOFF_KEYS = %w[
    instrumentation.excon
    instrumentation.mongo
    instrumentation.stripe
    instrumentation.rails_event_logger
  ].freeze

  module_function

  def generate(defaults = DEFAULTS)
    properties = {}
    defaults.sort_by { |key, _| key.to_s }.each do |key, spec|
      next unless public?(spec) && !deprecated?(spec)
      next if EXCLUDE_KEYS.include?(key)

      properties[key.to_s] = build_property(spec, enum_override_for(key, spec))
    end

    {
      '$schema' => SCHEMA_URI,
      'title' => 'New Relic Ruby Agent Configuration',
      'description' => 'Configuration settings for the New Relic Ruby agent. ' \
        'Generated from DEFAULTS in lib/new_relic/agent/configuration/default_source.rb.',
      'type' => 'object',
      # true (not false) on purpose: the agent ships new config keys every
      # release, and a Fleet Control deployment may validate against a schema
      # generated from an older agent. Strict validation would reject any newer
      # key and break users who upgrade before the schema is republished. Flip
      # to false only alongside a lockstep republish process.
      'additionalProperties' => true,
      'properties' => properties
    }
  end

  def build_property(spec, enum_override = nil)
    property = spec[:type] == Array ? ARRAY_OR_STRING.dup : {'type' => json_type(spec[:type])}

    description = description_for(spec)
    property['description'] = description if description

    default = default_for(spec)
    property['default'] = default unless default == OMIT

    enum = spec[:allowlist] ? spec[:allowlist].map(&:to_s) : enum_override
    property['enum'] = enum if enum
    property['writeOnly'] = true if spec[:exclude_from_reported_settings]

    property
  end

  # Enum values for a setting that has no :allowlist. Returns nil when the
  # setting isn't an enum. Only applies to string/symbol settings; :allowlist
  # always wins over an override.
  def enum_override_for(key, spec)
    return nil if spec[:allowlist]
    return nil unless [String, Symbol].include?(spec[:type])

    key = key.to_s
    return BASE_ENUM_OVERRIDES[key] if BASE_ENUM_OVERRIDES.key?(key)
    return nil unless key.start_with?('instrumentation.')

    INSTRUMENTATION_ONOFF_KEYS.include?(key) ? INSTRUMENTATION_ONOFF_VALUES : INSTRUMENTATION_STANDARD_VALUES
  end

  def to_json_string(defaults = DEFAULTS)
    # JSON.pretty_generate emits the array/object newline separators even for
    # empty containers, leaving an ugly blank indented line between the
    # brackets (e.g. an empty default []). Collapse those back to [] / {}.
    JSON.pretty_generate(generate(defaults))
      .gsub(/\[\s*\n\s*\]/, '[]')
      .gsub(/\{\s*\n\s*\}/, '{}')
  end

  def write_file(defaults = DEFAULTS, path = OUTPUT_PATH)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, rendered(defaults))
    path
  end

  # Write only when the generated schema differs from what's on disk (or the
  # file is missing). Returns :changed or :unchanged so CI can detect drift.
  def write_if_changed(defaults = DEFAULTS, path = OUTPUT_PATH)
    new_content = rendered(defaults)
    return :unchanged if File.exist?(path) && File.read(path) == new_content

    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, new_content)
    :changed
  end

  # CLI entry point. Exit codes drive the per-push regen workflow:
  # 0 = unchanged, 1 = changed (workflow commits), 2 = failure.
  # Validates against the Draft 2020-12 meta-schema first, so an invalid schema
  # fails (2) and is never written.
  def run(defaults = DEFAULTS, path = OUTPUT_PATH)
    errors = validate_schema(generate(defaults))
    unless errors.empty?
      warn "Generated schema failed Draft 2020-12 validation:\n#{errors.first(10).join("\n")}"
      return 2
    end

    if write_if_changed(defaults, path) == :unchanged
      puts "Schema unchanged: #{path}"
      0
    else
      puts "Schema changed, wrote: #{path}"
      1
    end
  rescue StandardError => e
    warn "Schema generation failed: #{e.class}: #{e.message}"
    2
  end

  # --- helpers ----------------------------------------------------------------

  # The exact bytes written to disk, so every writer stays byte-identical.
  def rendered(defaults)
    "#{to_json_string(defaults)}\n"
  end

  # Validate a schema against the Draft 2020-12 meta-schema. Returns an array of
  # error descriptions ([] when valid). Soft-skips (returns []) when json_schemer
  # isn't installed, validation is a safety net, not a hard dependency.
  def validate_schema(schema)
    unless defined?(JSONSchemer)
      warn 'Meta-schema validation skipped (json_schemer not installed).'
      return []
    end

    JSONSchemer.draft202012.validate(schema).map { |e| "#{e['data_pointer']}: #{e['type']}" }
  end

  def public?(spec)
    spec[:public] == true
  end

  def deprecated?(spec)
    spec[:deprecated] == true
  end

  def json_type(type)
    case type.to_s
    when Boolean.to_s then 'boolean'
    when 'Integer' then 'integer'
    when 'Float' then 'number'
    when 'Hash' then 'object'
    else 'string' # String, Symbol, and anything unmapped serialize as a string
    end
  end

  # Sentinel so a literal `nil` default (omit) is distinguishable from "no default".
  OMIT = Object.new

  def default_for(spec)
    value = spec[:documentation_default].nil? ? spec[:default] : spec[:documentation_default]
    return OMIT if value.nil? || value.is_a?(Proc)

    value.is_a?(Symbol) ? value.to_s : value
  end

  def description_for(spec)
    return nil if spec[:description].nil?

    cleaned = NewRelicYML.sanitize_description(spec[:description]).strip
    cleaned.empty? ? nil : cleaned
  end
end

exit(GenerateSchema.run) if __FILE__ == $PROGRAM_NAME
