# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'json'
require_relative '../generate_schema'

# Tests for the Fleet Control config schema generator. These exercise the
# building logic against controlled fake specs (the same approach as
# test/new_relic/newrelicyml_test.rb) so they don't churn when DEFAULTS changes.
class GenerateSchemaTest < Minitest::Test
  Boolean = NewRelic::Agent::Configuration::Boolean

  # --- top-level schema shape -------------------------------------------------

  def test_top_level_is_a_draft_2020_12_object_schema
    schema = GenerateSchema.generate(FAKE_DEFAULTS)

    assert_equal 'https://json-schema.org/draft/2020-12/schema', schema['$schema']
    assert_equal 'object', schema['type']
    # true (not false) on purpose: a config using a key newer than the schema
    # still validates, so upgrading the agent before the schema is republished
    # doesn't break Fleet Control validation.
    assert_equal true, schema['additionalProperties']
    assert_kind_of Hash, schema['properties']
  end

  def test_excludes_non_public_settings
    properties = GenerateSchema.generate(FAKE_DEFAULTS)['properties']

    refute properties.key?('secret_internal')
  end

  def test_excludes_deprecated_settings
    properties = GenerateSchema.generate(FAKE_DEFAULTS)['properties']

    refute properties.key?('old_setting')
  end

  def test_includes_public_non_deprecated_settings
    properties = GenerateSchema.generate(FAKE_DEFAULTS)['properties']

    assert properties.key?('agent_enabled')
    assert properties.key?('transaction_tracer.enabled')
  end

  def test_excludes_settings_not_configurable_via_yaml
    skip_key = GenerateSchema::EXCLUDE_KEYS.first
    defaults = {skip_key => {:default => false, :public => true, :type => Boolean, :description => 'env-only'}}

    refute GenerateSchema.generate(defaults)['properties'].key?(skip_key.to_s)
  end

  def test_property_keys_are_sorted_and_dotted_keys_preserved
    keys = GenerateSchema.generate(FAKE_DEFAULTS)['properties'].keys

    assert_equal keys.sort, keys
    assert_includes keys, 'transaction_tracer.enabled'
  end

  # --- per-property building --------------------------------------------------

  def test_boolean_property
    prop = GenerateSchema.build_property(:default => true, :type => Boolean)

    assert_equal 'boolean', prop['type']
    assert_equal true, prop['default']
  end

  def test_string_property
    assert_equal 'string', GenerateSchema.build_property(:type => String)['type']
  end

  def test_integer_property
    assert_equal 'integer', GenerateSchema.build_property(:type => Integer)['type']
  end

  def test_float_maps_to_number
    assert_equal 'number', GenerateSchema.build_property(:type => Float)['type']
  end

  def test_symbol_type_maps_to_string
    assert_equal 'string', GenerateSchema.build_property(:type => Symbol, :default => :high)['type']
  end

  def test_array_maps_to_anyof_array_or_delimited_string
    prop = GenerateSchema.build_property(:type => Array, :default => [])

    refute prop.key?('type')
    assert_equal(
      [{'type' => 'array', 'items' => {'type' => 'string'}}, {'type' => 'string'}],
      prop['anyOf']
    )
  end

  # --- enums ------------------------------------------------------------------

  def test_enum_from_string_allowlist
    prop = GenerateSchema.build_property(:type => String, :allowlist => %w[top middle end])

    assert_equal %w[top middle end], prop['enum']
  end

  def test_enum_coerces_symbol_allowlist_and_default_to_strings
    prop = GenerateSchema.build_property(:type => Symbol, :default => :high, :allowlist => %i[none low medium high])

    assert_equal %w[none low medium high], prop['enum']
    assert_equal 'high', prop['default']
  end

  # --- defaults ---------------------------------------------------------------

  def test_uses_documentation_default_when_present
    prop = GenerateSchema.build_property(:type => Boolean, :default => proc { true }, :documentation_default => true)

    assert_equal true, prop['default']
  end

  def test_omits_proc_default_with_no_documentation_default
    prop = GenerateSchema.build_property(:type => Boolean, :default => proc { true })

    refute prop.key?('default')
  end

  # --- sensitive values -------------------------------------------------------

  def test_write_only_for_settings_excluded_from_reported_settings
    prop = GenerateSchema.build_property(:type => String, :default => '', :exclude_from_reported_settings => true)

    assert_equal true, prop['writeOnly']
  end

  def test_not_write_only_by_default
    refute GenerateSchema.build_property(:type => String).key?('writeOnly')
  end

  # --- descriptions -----------------------------------------------------------

  def test_description_is_sanitized_and_stripped
    prop = GenerateSchema.build_property(:type => Boolean, :default => true,
      :description => 'If `true`, [does a thing](/docs/thing).')

    assert_equal 'If true, does a thing.', prop['description']
  end

  def test_blank_description_is_omitted
    refute GenerateSchema.build_property(:type => String).key?('description')
  end

  # --- enum overrides (settings that are enums but carry no :allowlist) --------

  def test_build_property_uses_enum_override_when_no_allowlist
    prop = GenerateSchema.build_property({:type => String}, %w[a b c])

    assert_equal %w[a b c], prop['enum']
  end

  def test_allowlist_takes_precedence_over_enum_override
    prop = GenerateSchema.build_property({:type => String, :allowlist => %w[x y]}, %w[a b c])

    assert_equal %w[x y], prop['enum']
  end

  def test_enum_override_for_core_settings
    assert_equal %w[debug info warn error fatal],
      GenerateSchema.enum_override_for('log_level', {:type => String})
    assert_equal %w[off none raw obfuscated],
      GenerateSchema.enum_override_for('transaction_tracer.record_sql', {:type => String})
    assert_equal %w[off none raw obfuscated],
      GenerateSchema.enum_override_for('slow_sql.record_sql', {:type => String})
  end

  def test_enum_override_for_instrumentation
    assert_equal GenerateSchema::INSTRUMENTATION_STANDARD_VALUES,
      GenerateSchema.enum_override_for('instrumentation.net_http', {:type => String})
    assert_equal %w[enabled disabled],
      GenerateSchema.enum_override_for('instrumentation.excon', {:type => String})
  end

  def test_enum_override_skips_non_string_allowlisted_and_unknown
    # Array-typed instrumentation setting is not a toggle
    assert_nil GenerateSchema.enum_override_for('instrumentation.active_support_notifications.active_support_events', {:type => Array})
    # allowlist wins, so no override
    assert_nil GenerateSchema.enum_override_for('security.mode', {:type => String, :allowlist => %w[IAST RASP]})
    # ordinary setting has no enum
    assert_nil GenerateSchema.enum_override_for('app_name', {:type => String})
  end

  def test_instrumentation_onoff_keys_matches_real_defaults
    onoff_description = /May be one of: `enabled`, `disabled`\./

    actual_onoff_keys = NewRelic::Agent::Configuration::DEFAULTS.select do |key, spec|
      key.to_s.start_with?('instrumentation.') &&
        spec[:type] == String &&
        !spec[:allowlist] &&
        spec[:description].to_s.match?(onoff_description)
    end.keys.map(&:to_s).sort

    assert_equal actual_onoff_keys, GenerateSchema::INSTRUMENTATION_ONOFF_KEYS.sort,
      'INSTRUMENTATION_ONOFF_KEYS in generate_schema.rb is out of sync with default_source.rb. ' \
      'If you added, removed, or changed an enabled/disabled-only instrumentation setting, update that list.'
  end

  def test_generate_applies_enum_overrides
    defaults = {
      :log_level => {:type => String, :default => 'info', :public => true, :description => 'x'},
      :'instrumentation.net_http' => {:type => String, :default => 'auto', :public => true, :description => 'x'}
    }
    props = GenerateSchema.generate(defaults)['properties']

    assert_equal %w[debug info warn error fatal], props['log_level']['enum']
    assert_equal GenerateSchema::INSTRUMENTATION_STANDARD_VALUES, props['instrumentation.net_http']['enum']
  end

  # --- rendering --------------------------------------------------------------

  def test_empty_array_default_renders_inline
    defaults = {:'labels.exclude' => {:type => Array, :default => [], :public => true, :description => 'x'}}

    json = GenerateSchema.to_json_string(defaults)

    assert_includes json, '"default": []'
    refute_match(/\[\s*\n\s*\]/, json) # no blank-line-inside-brackets
  end

  # --- writing the file -------------------------------------------------------

  def test_write_file_creates_missing_dirs_and_writes_valid_json
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'schemas', 'config.json')

      returned = GenerateSchema.write_file(FAKE_DEFAULTS, path)

      assert_equal path, returned
      assert File.exist?(path)
      assert_equal 'object', JSON.parse(File.read(path))['type']
    end
  end

  # --- change detection + exit codes (drives the CI drift check) --------------

  def test_write_if_changed_returns_changed_when_file_is_missing
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'schemas', 'config.json')

      assert_equal :changed, GenerateSchema.write_if_changed(FAKE_DEFAULTS, path)
      assert File.exist?(path)
    end
  end

  def test_write_if_changed_returns_unchanged_when_content_matches
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'config.json')
      GenerateSchema.write_file(FAKE_DEFAULTS, path)

      assert_equal :unchanged, GenerateSchema.write_if_changed(FAKE_DEFAULTS, path)
    end
  end

  def test_write_if_changed_rewrites_when_content_differs
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'config.json')
      File.write(path, "stale contents\n")

      assert_equal :changed, GenerateSchema.write_if_changed(FAKE_DEFAULTS, path)
      assert_equal 'object', JSON.parse(File.read(path))['type']
    end
  end

  def test_run_returns_exit_code_0_when_unchanged
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'config.json')
      GenerateSchema.write_file(FAKE_DEFAULTS, path)

      out, = capture_io do
        assert_equal 0, GenerateSchema.run(FAKE_DEFAULTS, path)
      end
      assert_match(/unchanged/i, out)
    end
  end

  def test_run_returns_exit_code_1_when_changed
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'config.json')

      capture_io do
        assert_equal 1, GenerateSchema.run(FAKE_DEFAULTS, path)
      end
    end
  end

  def test_run_returns_exit_code_2_on_failure
    Dir.mktmpdir do |dir|
      blocker = File.join(dir, 'blocker')
      File.write(blocker, 'x')
      # dirname is a regular file, so mkdir_p raises -> the failure path
      unwritable = File.join(blocker, 'config.json')

      capture_io do
        assert_equal 2, GenerateSchema.run(FAKE_DEFAULTS, unwritable)
      end
    end
  end

  # --- meta-schema validation in the generator --------------------------------

  # The generator validates its output against the Draft 2020-12 meta-schema
  # before writing, so an invalid schema fails with exit 2 and is never written.
  # Skipped where json_schemer isn't installed.
  def test_run_returns_exit_code_2_and_writes_nothing_when_schema_is_invalid
    skip 'json_schemer not installed' unless defined?(JSONSchemer)

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'config.json')
      invalid_schema = {'type' => 'not-a-real-type'}

      code = nil
      with_stubbed_generate(invalid_schema) do
        capture_io { code = GenerateSchema.run(FAKE_DEFAULTS, path) }
      end

      assert_equal 2, code
      refute_path_exists path, 'an invalid schema must not be written to disk'
    end
  end

  private

  # Temporarily replace GenerateSchema.generate so run/write see a chosen schema.
  def with_stubbed_generate(schema)
    original = GenerateSchema.method(:generate)
    GenerateSchema.define_singleton_method(:generate) { |*| schema }
    yield
  ensure
    GenerateSchema.define_singleton_method(:generate, original)
  end

  FAKE_DEFAULTS = {
    :agent_enabled => {
      :default => true,
      :public => true,
      :type => Boolean,
      :description => 'If `true`, allows the agent to run.'
    },
    :'transaction_tracer.enabled' => {
      :default => true,
      :public => true,
      :type => Boolean,
      :description => 'If `true`, enables collection of transaction traces.'
    },
    :secret_internal => {
      :default => 0.5,
      :public => false,
      :type => Float,
      :description => 'Internal knob users should not touch.'
    },
    :old_setting => {
      :default => false,
      :public => true,
      :deprecated => true,
      :type => Boolean,
      :description => 'This is deprecated.'
    }
  }
end
