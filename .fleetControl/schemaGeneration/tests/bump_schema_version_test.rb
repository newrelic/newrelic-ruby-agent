# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'json'
require_relative '../bump_schema_version'

# Tests for the bump driver's decide-and-write core. The git parts (finding the
# release tag, reading the previous schema) are thin glue exercised separately;
# apply is pure of git so it can be driven with fixtures.
class BumpSchemaVersionTest < Minitest::Test
  def schema(properties)
    {'type' => 'object', 'properties' => properties}
  end

  def with_config_def(version)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'configurationDefinitions.yml')
      File.write(path, "configurationDefinitions:\n  - platform: KUBERNETESCLUSTER\n    version: #{version}\n    format: yml\n")
      yield path
    end
  end

  def version_in(path)
    File.read(path)[/^\s*version:\s*(\S+)/, 1]
  end

  def test_apply_first_release_writes_nothing
    with_config_def('1.0.0') do |path|
      result = BumpSchemaVersion.apply(baseline: nil, current: schema({}), starter_version: nil, config_def_path: path, write: true)

      assert_equal :first_release, result[:action]
      assert_equal '1.0.0', version_in(path)
    end
  end

  def test_apply_no_change_writes_nothing
    s = schema('a' => {'type' => 'string'})
    with_config_def('1.0.0') do |path|
      result = BumpSchemaVersion.apply(baseline: s, current: s, starter_version: '1.0.0', config_def_path: path, write: true)

      assert_equal :no_change, result[:action]
      assert_equal '1.0.0', version_in(path)
    end
  end

  def test_apply_dry_run_recommends_without_writing
    baseline = schema('a' => {'type' => 'string'})
    current = schema('a' => {'type' => 'string'}, 'b' => {'type' => 'boolean'})
    with_config_def('1.2.0') do |path|
      result = BumpSchemaVersion.apply(baseline: baseline, current: current, starter_version: '1.2.0', config_def_path: path, write: false)

      assert_equal :bump, result[:action]
      assert_equal '1.3.0', result[:new_version]
      assert_equal '1.2.0', version_in(path) # not written
    end
  end

  def test_apply_write_updates_the_version_line
    baseline = schema('a' => {'type' => 'string'})
    current = schema('a' => {'type' => 'string'}, 'b' => {'type' => 'boolean'})
    with_config_def('1.2.0') do |path|
      BumpSchemaVersion.apply(baseline: baseline, current: current, starter_version: '1.2.0', config_def_path: path, write: true)

      assert_equal '1.3.0', version_in(path)
    end
  end

  def test_apply_write_is_idempotent_when_already_at_target
    baseline = schema('a' => {'type' => 'string'})
    current = schema('a' => {'type' => 'string'}, 'b' => {'type' => 'boolean'})
    with_config_def('1.3.0') do |path| # already at the bumped version
      BumpSchemaVersion.apply(baseline: baseline, current: current, starter_version: '1.2.0', config_def_path: path, write: true)

      assert_equal '1.3.0', version_in(path) # unchanged, no double-bump, no error
    end
  end
end
