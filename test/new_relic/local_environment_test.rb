# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..', 'test_helper'))
class NewRelic::LocalEnvironmentTest < Test::Unit::TestCase

  def self.teardown
    # To remove mock server instances from ObjectSpace
    ObjectSpace.garbage_collect
    super
  end
  class MockOptions
    def fetch (*args)
      1000
    end
  end
  MOCK_OPTIONS = MockOptions.new

  def test_passenger
    class << self
      module ::PhusionPassenger
      end
    end
    NewRelic::Agent.reset_config
    e = NewRelic::LocalEnvironment.new
    assert_equal :passenger, e.discovered_dispatcher
    assert_equal :passenger, NewRelic::Agent.config[:dispatcher]

    with_config(:app_name => 'myapp') do
      e = NewRelic::LocalEnvironment.new
      assert_equal :passenger, e.discovered_dispatcher
    end

  ensure
    Object.send(:remove_const, :PhusionPassenger)
  end

  # LocalEnvironment won't talk to ObjectSpace on JRuby, and these tests are
  # around that interaction, so we don't run them on JRuby.
  unless defined?(JRuby)
    def test_mongrel_only_checks_once
      return unless NewRelic::LanguageSupport.object_space_usable?

      define_mongrel

      # One call from LocalEnvironment's initialize, second from first #mongrel call.
      # All the rest shouldn't call into ObjectSpace
      ObjectSpace.expects(:each_object).with(::Mongrel::HttpServer).twice

      e = NewRelic::LocalEnvironment.new
      5.times { e.mongrel }
      assert_nil e.mongrel
    ensure
      Object.send(:remove_const, :Mongrel) if defined?(Mongrel)
    end

    def test_check_for_mongrel_allows_one_more_check
      return unless NewRelic::LanguageSupport.object_space_usable?

      define_mongrel

      ObjectSpace.expects(:each_object).with(::Mongrel::HttpServer).at_least(2)

      e = NewRelic::LocalEnvironment.new
      e.send(:check_for_mongrel)
    ensure
      Object.send(:remove_const, :Mongrel) if defined?(Mongrel)
    end
  end

  def define_mongrel
    class << self
      module ::Mongrel
        class HttpServer
        end
      end
    end
  end
end
