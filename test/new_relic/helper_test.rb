# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'ostruct'
require_relative '../test_helper'

# tests NewRelic::Helper
class HelperTest < Minitest::Test
  #
  # executable_in_path?
  #
  def test_executable_is_in_path
    executable = 'seagulls'
    fake_dir = '/usr/local/existent'
    ENV.stubs(:[]).with('PATH').returns(fake_dir)

    executable_path = File.join(fake_dir, executable)
    File.stubs(:exist?).with(executable_path).returns(true)
    File.stubs(:file?).with(executable_path).returns(true)
    File.stubs(:executable?).with(executable_path).returns(true)
    exists = NewRelic::Helper.executable_in_path?(executable)

    assert_truthy exists
  end

  def test_executable_is_not_in_path
    executable = 'seagulls'
    fake_dir = '/dev/null/nonexistent'
    ENV.stubs(:[]).with('PATH').returns(fake_dir)
    executable_path = File.join(fake_dir, executable)
    File.stubs(:exist?).with(executable_path).returns(false)
    exists = NewRelic::Helper.executable_in_path?(executable)

    assert_false exists
  end

  def test_path_does_not_exist
    ENV.stubs(:[]).with('PATH').returns(nil)
    exists = NewRelic::Helper.executable_in_path?('Whisper of the Heart')

    assert_false exists
  end

  #
  # run_command
  #
  def test_run_command_when_executable_does_not_exist
    NewRelic::Helper.stubs('executable_in_path?').returns(false)
    assert_raises(NewRelic::CommandExecutableNotFoundError) do
      NewRelic::Helper.run_command('mksh -v')
    end
  end

  def test_run_command_happy
    stubbed = 'Jinba ittai'
    NewRelic::Helper.stubs('executable_in_path?').returns(true)
    Open3.stubs('capture2e').returns([stubbed, OpenStruct.new(success?: true)])
    result = NewRelic::Helper.run_command('figlet Zoom Zoom')

    assert_equal result, stubbed
  end

  def test_run_command_sad_unsuccessful
    NewRelic::Helper.stubs('executable_in_path?').returns(true)
    Open3.stubs('capture2e').returns([nil, OpenStruct.new(success?: false)])
    assert_raises(NewRelic::CommandRunFailedError) do
      NewRelic::Helper.run_command('find / -name tetris')
    end
  end

  def test_run_command_sad_exception
    exception = StandardError.new("I'm going to have to put you on the game grid.")
    NewRelic::Helper.stubs('executable_in_path?').returns(true)
    Open3.stubs('capture2e').raises(exception)
    assert_raises(NewRelic::CommandRunFailedError, "#{exception.class} - #{exception.message}") do
      NewRelic::Helper.run_command('executable that existed at detection time but is not there now')
    end
  end

  #
  # version_satisfied?
  #
  def test_version_satisfied_greater_than
    assert(NewRelic::Helper.version_satisfied?('1.2.3', '<', '1.2.4'))
    assert_false(NewRelic::Helper.version_satisfied?('1.2.3', '<', '1.2.3'))
    assert(NewRelic::Helper.version_satisfied?(1, '<', 2))
    assert(NewRelic::Helper.version_satisfied?(1.2, '<', 1.3))
    assert(NewRelic::Helper.version_satisfied?(Gem::Version.new('1.2'), '<', Gem::Version.new('1.3')))
    assert(NewRelic::Helper.version_satisfied?('', '<', 1))
    assert(NewRelic::Helper.version_satisfied?('1.2', '<', 1.3))
  end

  def test_version_satisfied_greater_than_or_equal_to
    assert(NewRelic::Helper.version_satisfied?('1.2.3', '<=', '1.2.4'))
    assert_false(NewRelic::Helper.version_satisfied?('1.2.3', '<=', '1.2.2'))
    assert(NewRelic::Helper.version_satisfied?(1, '<=', 2))
    assert(NewRelic::Helper.version_satisfied?(1.2, '<=', 1.3))
    assert(NewRelic::Helper.version_satisfied?(Gem::Version.new('1.2'), '<=', Gem::Version.new('1.3')))
    assert(NewRelic::Helper.version_satisfied?('', '<=', 1))
    assert(NewRelic::Helper.version_satisfied?('1.2', '<=', 1.3))
  end

  def test_version_satisfied_less_than
    assert(NewRelic::Helper.version_satisfied?('1.2.3', '>', '1.2.2'))
    assert_false(NewRelic::Helper.version_satisfied?('1.2.3', '>', '1.2.3'))
    assert(NewRelic::Helper.version_satisfied?(2, '>', 1))
    assert(NewRelic::Helper.version_satisfied?(1.3, '>', 1.2))
    assert(NewRelic::Helper.version_satisfied?(Gem::Version.new('1.3'), '>', Gem::Version.new('1.2')))
    assert(NewRelic::Helper.version_satisfied?(1, '>', ''))
    assert(NewRelic::Helper.version_satisfied?(1.3, '>', '1.2'))
  end

  def test_version_satisfied_less_than_or_equal_to
    assert(NewRelic::Helper.version_satisfied?('1.2.3', '>=', '1.2.2'))
    assert_false(NewRelic::Helper.version_satisfied?('1.2.3', '>=', '1.2.4'))
    assert(NewRelic::Helper.version_satisfied?(2, '>=', 1))
    assert(NewRelic::Helper.version_satisfied?(1.3, '>=', 1.2))
    assert(NewRelic::Helper.version_satisfied?(Gem::Version.new('1.3'), '>=', Gem::Version.new('1.2')))
    assert(NewRelic::Helper.version_satisfied?(1, '>=', ''))
    assert(NewRelic::Helper.version_satisfied?(1.3, '>=', '1.2'))
  end

  #
  # rubygems_specs
  #
  def test_rubygems_specs_returns_empty_array_without_bundler
    stub(:defined?, nil, ['Bundler']) do
      result = NewRelic::Helper.rubygems_specs

      assert_instance_of Array, result
      assert_empty Array, result
    end
  end

  def test_rubygems_specs_works_with_all_specs_when_installed_specs_is_absent
    skip 'all_specs has been removed in Bundler 4.0+' if Gem::Version.new(Bundler::VERSION) >= Gem::Version.new('4.0.0')

    Bundler.rubygems.stub(:respond_to?, nil) do
      assert_equal Bundler.rubygems.all_specs, NewRelic::Helper.rubygems_specs
    end
  end

  def test_rubygems_specs_works_with_installed_specs
    skip 'running a version of Bundler that has not defined installed_specs' unless Bundler.rubygems.respond_to?(:installed_specs)

    assert_equal Bundler.rubygems.installed_specs, NewRelic::Helper.rubygems_specs
  end
end
