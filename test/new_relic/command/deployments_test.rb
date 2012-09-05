require File.expand_path(File.join(File.dirname(__FILE__),'/../../test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__),'/../../../lib/new_relic/command'))

class NewRelic::Command::DeploymentsTest < Test::Unit::TestCase

  def setup
    NewRelic::Command::Deployments.class_eval do
      attr_accessor :messages, :exit_status, :errors, :revision
      def err(message); @errors = @errors ? @errors + message : message; end
      def info(message); @messages = @messages ? @messages + message : message; end
      def just_exit(status=0); @exit_status ||= status; end
    end
    @config = { :license_key => 'a' * 40 }
    NewRelic::Agent.config.apply_config(@config)
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
      NewRelic::Command::Deployments.new "-h"
      fail "should have thrown"
    rescue NewRelic::Command::CommandFailure => c
      assert_match /^Usage/, c.message
    end
  end
  def test_bad_command
    assert_raise NewRelic::Command::CommandFailure do
      NewRelic::Command::Deployments.new ["-foo", "bar"]
    end
  end
  def test_interactive
    mock_the_connection
    @deployment = NewRelic::Command::Deployments.new(:appname => 'APP',
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
    @deployment = NewRelic::Command::Deployments.new(%w[-a APP -r 3838 --user=Bill] << "Some lengthy description")
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
      assert_raise NewRelic::Command::CommandFailure do
      deployment = NewRelic::Command::Deployments.new(%w[-a APP -r 3838 --user=Bill] << "Some lengthy description")
        deployment.run
      end
    end
  end

  private

  def mock_the_connection
    mock_connection = mock()
    @mock_response = mock()
    @mock_response.expects(:is_a?).with(Net::HTTPSuccess).returns(true)
    mock_connection.expects(:request).returns(@mock_response)
    NewRelic::Control.instance.stubs(:http_connection).returns(mock_connection)
  end
end
