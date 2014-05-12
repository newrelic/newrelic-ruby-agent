# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..', 'test_helper'))
class NewRelic::LocalEnvironmentTest < Minitest::Test

  def teardown
    NewRelic::Control.reset
  end

  def test_passenger
    with_constant_defined(:PhusionPassenger, Module.new) do
      NewRelic::Agent.reset_config
      e = NewRelic::LocalEnvironment.new
      assert_equal :passenger, e.discovered_dispatcher
      assert_equal :passenger, NewRelic::Agent.config[:dispatcher]

      with_config(:app_name => 'myapp') do
        e = NewRelic::LocalEnvironment.new
        assert_equal :passenger, e.discovered_dispatcher
      end
    end
  end

  # LocalEnvironment won't talk to ObjectSpace on JRuby, and these tests are
  # around that interaction, so we don't run them on JRuby.
  unless defined?(JRuby)
    def test_mongrel_only_checks_once
      return unless NewRelic::LanguageSupport.object_space_usable?

      with_constant_defined(:'Mongrel', Module.new) do
        with_constant_defined(:'Mongrel::HttpServer', Class.new) do
          ObjectSpace.expects(:each_object).with(::Mongrel::HttpServer).once

          e = NewRelic::LocalEnvironment.new
          5.times { e.mongrel }
          assert_nil e.mongrel
        end
      end
    end
  end
end
