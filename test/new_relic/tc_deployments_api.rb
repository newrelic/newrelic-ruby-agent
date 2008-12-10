require File.expand_path(File.join(File.dirname(__FILE__),'/../test_helper'))
#require 'new_relic/api/deployments'
class NewRelic::DeploymentsTests < Test::Unit::TestCase
  
  def setup
    NewRelic::API::Deployments.any_instance.stubs(:just_exit)
    NewRelic::API::Deployments.class_eval do
      attr_accessor :messages, :exit_status, :errors, :env
      def err(message); @errors = @errors ? @errors + message : message; end
      def info(message); @messages = @messages ? @messages + message : message; end
      def just_exit(status=0); @exit_status ||= status; end
      def set_env(env); @env = env; end
    end
  end
  def teardown
    return unless @deployment
    puts @deployment.errors
    puts @deployment.messages
    puts @deployment.exit_status
  end
  def test_help
    @deployment = NewRelic::API::Deployments.new "-h"
    assert_equal 0, @deployment.exit_status
    assert_match /^Usage/, @deployment.messages
    assert_nil @deployment.env
    @deployment = nil
  end
  def test_run
    @deployment = NewRelic::API::Deployments.new %w[-a APP --user=Bill -e dev] << "Some lengthy description"
    assert_nil @deployment.exit_status
    assert_nil @deployment.errors
    assert_equal 'dev', @deployment.env
    @deployment.run
    assert_equal 1, @deployment.exit_status
    assert_match /Unable to upload/, @deployment.errors
    @deployment = nil
  end
  
end
