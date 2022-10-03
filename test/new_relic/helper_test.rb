# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

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
end
