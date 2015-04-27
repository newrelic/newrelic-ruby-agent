# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/cli/command'
require 'new_relic/cli/commands/install'

class NewRelic::Cli::InstallTest < Minitest::Test
  def test_fails_without_app_name
    assert_raises(NewRelic::Cli::Command::CommandFailure) do
      NewRelic::Cli::Install.new(["-l", "license"])
    end
  end

  def test_basic_run
    install = NewRelic::Cli::Install.new(["-l", "license", "app"])
    assert_equal "license", install.license_key
    assert_equal "app", install.app_name
  end

  def test_app_name_with_spaces
    install = NewRelic::Cli::Install.new(["-l", "license", "my", "app"])
    assert_equal "license", install.license_key
    assert_equal "my app", install.app_name
  end
end
