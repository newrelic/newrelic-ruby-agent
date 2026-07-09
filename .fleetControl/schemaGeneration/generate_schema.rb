#!/usr/bin/env ruby
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative '../../lib/new_relic/agent/configuration/default_source'
# Reused for description cleanup so the schema, the config docs, and the
# generated newrelic.yml all strip markdown the same way (no drift).
require_relative '../../lib/tasks/helpers/newrelicyml'

# Generates a JSON Schema (Draft 2020-12) describing the New Relic Ruby agent's
# configuration, read straight from NewRelic::Agent::Configuration::DEFAULTS.
# This is the Ruby parallel to the Java agent's GenerateSchema.groovy, and feeds
# the same Fleet Control consumption path (../schemas/config.json).
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
  # in DEFAULTS. The Java agent keeps an equivalent ENUM_OVERRIDES map. Values
  # are verified against the code that consumes each setting, NOT the prose
  # descriptions (which omit log_level's `fatal` and mislabel `to_app`):
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

  # instrumentation.* toggles. Most accept the standard set
  # (dependency_detection.rb VALID_CONFIG_VALUES); a few are simple on/off.
  INSTRUMENTATION_STANDARD_VALUES = %w[auto prepend chain disabled].freeze
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
      # true (not false), matching the Java agent: the agent ships new config
      # keys every release, and a Fleet Control deployment may validate against
      # a schema generated from an older agent. Strict validation would reject
      # any newer key and break users who upgrade before the schema is
      # republished. Flip to false only alongside a lockstep republish process.
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
    File.write(path, "#{to_json_string(defaults)}\n")
    path
  end

  # --- helpers ----------------------------------------------------------------

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

GenerateSchema.write_file && (puts "Wrote #{GenerateSchema::OUTPUT_PATH}") if __FILE__ == $PROGRAM_NAME
