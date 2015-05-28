# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/cli/command'
require 'new_relic/cli/commands/deployments'

class NewRelic::Cli::DeploymentsTest < Minitest::Test

  def setup
    NewRelic::Cli::Deployments.class_eval do
      attr_accessor :messages, :exit_status, :errors, :revision, :license_key
      def err(message); @errors = @errors ? @errors + message : message; end
      def info(message); @messages = @messages ? @messages + message : message; end
      def just_exit(status=0); @exit_status ||= status; end
    end
    @config = { :license_key => 'a' * 40,
                :config_path => 'test/config/newrelic.yml' }
    NewRelic::Agent.config.add_config_for_testing(@config)
  end

  def teardown
    super
    return unless @deployment
    puts @deployment.errors
    puts @deployment.messages
    puts @deployment.exit_status
    NewRelic::Agent.config.remove_config(@config)
  end


  def test_help
    begin
      NewRelic::Cli::Deployments.new "-h"
      fail "should have thrown"
    rescue NewRelic::Cli::Command::CommandFailure => c
      assert_match(/^Usage/, c.message)
    end
  end

  def test_bad_command
    assert_raises NewRelic::Cli::Command::CommandFailure do
      NewRelic::Cli::Deployments.new ["-foo", "bar"]
    end
  end

  def test_interactive
    mock_the_connection
    @deployment = NewRelic::Cli::Deployments.new(:appname => 'APP',
                                  :revision => 3838,
                                  :user => 'Bill',
                                  :description => "Some lengthy description")
    assert_nil @deployment.exit_status
    assert_nil @deployment.errors
    assert_equal '3838', @deployment.revision
    @deployment.run
    @deployment = nil
  end

  def test_command_line_run
    mock_the_connection
    #    @mock_response.expects(:body).returns("<xml>deployment</xml>")
    @deployment = NewRelic::Cli::Deployments.new(%w[-a APP -r 3838 --user=Bill] << "Some lengthy description")
    assert_nil @deployment.exit_status
    assert_nil @deployment.errors
    assert_equal '3838', @deployment.revision
    @deployment.run

    # This should pass because it's a bogus deployment
    #assert_equal 1, @deployment.exit_status
    #assert_match /Unable to upload/, @deployment.errors

    @deployment = nil
  end

  def test_error_if_no_license_key
    with_config(:license_key => '') do
      assert_raises NewRelic::Cli::Command::CommandFailure do
        deployment = NewRelic::Cli::Deployments.new(%w[-a APP -r 3838 --user=Bill] << "Some lengthy description")
        deployment.run
      end
    end
  end

  def test_error_if_failed_yaml
    NewRelic::Agent::Configuration::YamlSource.any_instance.stubs(:failed?).returns(true)

    assert_raises NewRelic::Cli::Command::CommandFailure do
      deployment = NewRelic::Cli::Deployments.new(%w[-a APP -r 3838 --user=Bill] << "Some lengthy description")
      deployment.run
    end
  end

  def test_with_specified_license_key
    mock_the_connection
    @deployment = NewRelic::Cli::Deployments.new(:appname => 'APP',
                                                     :revision => 3838,
                                                     :user => 'Bill',
                                                     :description => "Some lengthy description",
                                                     :license_key => 'b' * 40)
    assert_nil @deployment.exit_status
    assert_nil @deployment.errors
    assert_equal 'b' * 40, @deployment.license_key
    @deployment.run
    @deployment = nil
  end

  def test_with_unspecified_license_key
    mock_the_connection
    @deployment = NewRelic::Cli::Deployments.new(:appname => 'APP',
                                                     :revision => 3838,
                                                     :user => 'Bill',
                                                     :description => "Some lengthy description")
    assert_nil @deployment.exit_status
    assert_nil @deployment.errors
    assert_equal 'a' * 40, @deployment.license_key
    @deployment.run
    @deployment = nil
  end

  private

  def mock_the_connection
    mock_connection = mock()
    @mock_response = mock()
    @mock_response.expects(:is_a?).with(Net::HTTPSuccess).returns(true)
    mock_connection.expects(:request).returns(@mock_response)
    NewRelic::Agent::NewRelicService.any_instance.stubs(:http_connection).returns(mock_connection)
  end
end
