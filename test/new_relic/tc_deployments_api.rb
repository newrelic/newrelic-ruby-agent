require File.expand_path(File.join(File.dirname(__FILE__),'/../test_helper'))
require 'new_relic_api'
class NewRelic::DeploymentsTests < Test::Unit::TestCase
  
  def setup
    NewRelic::API::Deployments.class_eval do
      attr_accessor :messages, :exit_status, :errors, :revision
      def err(message); @errors = @errors ? @errors + message : message; end
      def info(message); @messages = @messages ? @messages + message : message; end
      def just_exit(status=0); @exit_status ||= status; end
    end
  end
  def teardown
    return unless @deployment
    puts @deployment.errors
    puts @deployment.messages
    puts @deployment.exit_status
  end
  def test_help
    @deployment = NewRelic::API::Deployments.new "-?"
    assert_equal 0, @deployment.exit_status
    assert_match /^Usage/, @deployment.messages
    assert_nil @deployment.revision
    @deployment = nil
  end
  def test_run
    @deployment = NewRelic::API::Deployments.new(%w[-a APP -r 3838 --user=Bill] << "Some lengthy description")
    assert_nil @deployment.exit_status
    assert_nil @deployment.errors
    assert_equal '3838', @deployment.revision
    @deployment.run
    assert_equal 1, @deployment.exit_status
    assert_match /Unable to upload/, @deployment.errors
    @deployment = nil
  end
  
end
