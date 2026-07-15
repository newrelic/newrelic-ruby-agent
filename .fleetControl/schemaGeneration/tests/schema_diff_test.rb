# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'json'
require_relative '../schema_diff'

# Tests for the schema diff/bump logic. Everything here is pure (no git, no
# release tags) so the classification and version arithmetic can be exercised
# against controlled fixtures.
class SchemaDiffTest < Minitest::Test
  # Build a minimal schema whose properties are the given hash.
  def schema(properties)
    {'type' => 'object', 'properties' => properties}
  end

  # --- classify_changes: property-level ---------------------------------------

  def test_no_changes_returns_empty
    s = schema('a' => {'type' => 'string'})

    assert_empty SchemaDiff.classify_changes(s, s)
  end

  def test_property_added_is_additive
    old = schema({})
    new = schema('a' => {'type' => 'string'})

    change = SchemaDiff.classify_changes(old, new).fetch(0)
    assert_equal 'property_added', change[:kind]
    assert_equal 'additive', change[:severity]
    assert_equal 'a', change[:path]
  end

  def test_property_removed_is_breaking
    old = schema('a' => {'type' => 'string'})
    new = schema({})

    change = SchemaDiff.classify_changes(old, new).fetch(0)
    assert_equal 'property_removed', change[:kind]
    assert_equal 'breaking', change[:severity]
  end

  def test_dotted_keys_are_reported_verbatim
    old = schema({})
    new = schema('transaction_tracer.enabled' => {'type' => 'boolean'})

    assert_equal 'transaction_tracer.enabled', SchemaDiff.classify_changes(old, new).fetch(0)[:path]
  end

  # --- classify_leaf: property internals --------------------------------------

  def leaf_change(old_prop, new_prop)
    SchemaDiff.classify_changes(schema('k' => old_prop), schema('k' => new_prop)).fetch(0)
  end

  def test_type_changed_is_breaking
    change = leaf_change({'type' => 'string'}, {'type' => 'integer'})

    assert_equal 'type_changed', change[:kind]
    assert_equal 'breaking', change[:severity]
  end

  def test_type_change_between_string_and_array_or_string_is_breaking
    array_or_string = {'anyOf' => [{'type' => 'array', 'items' => {'type' => 'string'}}, {'type' => 'string'}]}

    assert_equal 'type_changed', leaf_change({'type' => 'string'}, array_or_string)[:kind]
  end

  def test_enum_introduced_is_breaking
    change = leaf_change({'type' => 'string'}, {'type' => 'string', 'enum' => %w[a b]})

    assert_equal 'enum_introduced', change[:kind]
    assert_equal 'breaking', change[:severity]
  end

  def test_enum_removed_entirely_is_additive
    change = leaf_change({'type' => 'string', 'enum' => %w[a b]}, {'type' => 'string'})

    assert_equal 'enum_removed_entirely', change[:kind]
    assert_equal 'additive', change[:severity]
  end

  def test_enum_value_removed_is_breaking
    change = leaf_change({'enum' => %w[a b c]}, {'enum' => %w[a b]})

    assert_equal 'enum_value_removed', change[:kind]
    assert_equal 'breaking', change[:severity]
  end

  def test_enum_value_added_is_additive
    change = leaf_change({'enum' => %w[a b]}, {'enum' => %w[a b c]})

    assert_equal 'enum_value_added', change[:kind]
    assert_equal 'additive', change[:severity]
  end

  def test_enum_values_added_and_removed_together_is_breaking
    changes = SchemaDiff.classify_changes(
      schema('k' => {'enum' => %w[a b]}),
      schema('k' => {'enum' => %w[a c]})
    )
    kinds = changes.map { |change| change[:kind] }

    assert_equal 2, changes.size
    assert_includes kinds, 'enum_value_removed'
    assert_includes kinds, 'enum_value_added'
    assert_equal 'major', SchemaDiff.recommend_bump(changes)
  end

  def test_default_changed_is_additive
    change = leaf_change({'type' => 'integer', 'default' => 1}, {'type' => 'integer', 'default' => 2})

    assert_equal 'default_changed', change[:kind]
    assert_equal 'additive', change[:severity]
  end

  def test_description_changed_is_cosmetic
    change = leaf_change({'description' => 'old'}, {'description' => 'new'})

    assert_equal 'description_changed', change[:kind]
    assert_equal 'cosmetic', change[:severity]
  end

  # --- recommend_bump ---------------------------------------------------------

  def test_recommend_bump_any_breaking_is_major
    changes = [{severity: 'cosmetic'}, {severity: 'breaking'}, {severity: 'additive'}]

    assert_equal 'major', SchemaDiff.recommend_bump(changes)
  end

  def test_recommend_bump_additive_without_breaking_is_minor
    assert_equal 'minor', SchemaDiff.recommend_bump([{severity: 'cosmetic'}, {severity: 'additive'}])
  end

  def test_recommend_bump_cosmetic_only_is_patch
    assert_equal 'patch', SchemaDiff.recommend_bump([{severity: 'cosmetic'}])
  end

  def test_recommend_bump_no_changes_is_none
    assert_equal 'none', SchemaDiff.recommend_bump([])
  end

  # --- apply_bump -------------------------------------------------------------

  def test_apply_bump_major_resets_minor_and_patch
    assert_equal '2.0.0', SchemaDiff.apply_bump('1.2.3', 'major')
  end

  def test_apply_bump_minor_resets_patch
    assert_equal '1.3.0', SchemaDiff.apply_bump('1.2.3', 'minor')
  end

  def test_apply_bump_patch_increments_patch
    assert_equal '1.2.4', SchemaDiff.apply_bump('1.2.3', 'patch')
  end

  def test_apply_bump_none_is_unchanged
    assert_equal '1.2.3', SchemaDiff.apply_bump('1.2.3', 'none')
  end

  def test_apply_bump_rejects_non_semver
    assert_raises(ArgumentError) { SchemaDiff.apply_bump('not-semver', 'minor') }
  end

  def test_apply_bump_rejects_unknown_bump
    assert_raises(ArgumentError) { SchemaDiff.apply_bump('1.2.3', 'sideways') }
  end

  # --- load_existing ----------------------------------------------------------

  def test_load_existing_parses_valid_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'config.json')
      File.write(path, JSON.generate('type' => 'object'))

      assert_equal({'type' => 'object'}, SchemaDiff.load_existing(path))
    end
  end

  def test_load_existing_returns_empty_hash_when_missing
    assert_equal({}, SchemaDiff.load_existing('/no/such/file.json'))
  end

  def test_load_existing_returns_empty_hash_when_malformed
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'config.json')
      File.write(path, 'not json{')

      assert_equal({}, SchemaDiff.load_existing(path))
    end
  end

  # --- bump_version_line ------------------------------------------------------

  def test_bump_version_line_replaces_only_the_version_line
    yaml = "configurationDefinitions:\n  - platform: KUBERNETESCLUSTER\n    version: 1.2.0\n    format: yml\n"

    result = SchemaDiff.bump_version_line(yaml, '2.0.0')

    assert_includes result, 'version: 2.0.0'
    assert_includes result, 'platform: KUBERNETESCLUSTER'
    assert_includes result, 'format: yml'
    refute_includes result, '1.2.0'
  end

  def test_bump_version_line_raises_when_no_version_line
    assert_raises(RuntimeError) { SchemaDiff.bump_version_line("platform: x\n", '2.0.0') }
  end

  def test_bump_version_line_raises_when_multiple_version_lines
    yaml = "    version: 1.0.0\n    version: 2.0.0\n"

    assert_raises(RuntimeError) { SchemaDiff.bump_version_line(yaml, '3.0.0') }
  end

  # --- render_change ----------------------------------------------------------

  def test_render_change_marks_added_removed_and_modified
    added = SchemaDiff.render_change(path: 'a', kind: 'property_added', severity: 'additive', detail: 'new property')
    removed = SchemaDiff.render_change(path: 'b', kind: 'property_removed', severity: 'breaking', detail: 'removed')
    modified = SchemaDiff.render_change(path: 'c', kind: 'type_changed', severity: 'breaking', detail: 'string -> integer')

    assert_match(/\A\+ /, added)
    assert_match(/\A- /, removed)
    assert_match(/\A~ /, modified)
    assert_includes added, 'a'
  end

  # --- bump: decision from the previous release -------------------------------

  def test_bump_first_release_when_no_baseline
    result = SchemaDiff.bump(baseline: {}, current: schema('a' => {'type' => 'string'}), starter_version: '1.0.0')

    assert_equal :first_release, result[:action]
    assert_equal 'none', result[:bump]
  end

  def test_bump_first_release_when_baseline_nil
    assert_equal :first_release, SchemaDiff.bump(baseline: nil, current: schema({}), starter_version: '1.0.0')[:action]
  end

  def test_bump_first_release_when_starter_version_missing
    baseline = schema('a' => {'type' => 'string'})
    current = schema('a' => {'type' => 'string'}, 'b' => {'type' => 'boolean'})

    assert_equal :first_release, SchemaDiff.bump(baseline: baseline, current: current, starter_version: nil)[:action]
  end

  def test_bump_no_change_when_schema_matches_baseline
    s = schema('a' => {'type' => 'string'})

    result = SchemaDiff.bump(baseline: s, current: s, starter_version: '1.0.0')

    assert_equal :no_change, result[:action]
    assert_equal 'none', result[:bump]
  end

  def test_bump_recommends_and_applies_to_starter_version
    baseline = schema('a' => {'type' => 'string'})
    current = schema('a' => {'type' => 'string'}, 'b' => {'type' => 'boolean'})

    result = SchemaDiff.bump(baseline: baseline, current: current, starter_version: '1.2.0')

    assert_equal :bump, result[:action]
    assert_equal 'minor', result[:bump]
    assert_equal '1.2.0', result[:old_version]
    assert_equal '1.3.0', result[:new_version]
  end

  def test_bump_uses_starter_version_not_current_so_reruns_match
    baseline = schema('a' => {'type' => 'string'})
    current = schema('a' => {'type' => 'string'}, 'b' => {'type' => 'boolean'})

    first = SchemaDiff.bump(baseline: baseline, current: current, starter_version: '1.2.0')
    again = SchemaDiff.bump(baseline: baseline, current: current, starter_version: '1.2.0')

    assert_equal first[:new_version], again[:new_version] # same release baseline -> same result
    assert_equal '1.3.0', again[:new_version]
  end
end
