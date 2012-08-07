require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/configuration/manager'

module NewRelic::Agent::Configuration
  class ManagerTest < Test::Unit::TestCase
    def setup
      @manager = NewRelic::Agent::Configuration.manager
    end

    def teardown
      default_source = NewRelic::Agent::Configuration::DEFAULTS
      @manager.instance_variable_set(:@config_stack, [ default_source ])
    end

    def test_should_apply_config_sources_in_order
      @manager.apply_config({'foo' => 'default foo', 'bar' => 'default bar', 'baz' => 'default baz'})
      @manager.apply_config({'foo' => 'real foo'})
      @manager.apply_config({'foo' => 'wrong foo', 'bar' => 'real bar'}, 1)

      assert_equal 'real foo', @manager['foo']
      assert_equal 'real bar', @manager['bar']
      assert_equal 'default baz', @manager['baz']
    end

    def test_identifying_config_source
      @manager.apply_config({'foo' => 'foo', 'bar' => 'default'})
      test_source = TestSource.new
      test_source['bar'] = 'bar'
      test_source['baz'] = 'baz'
      @manager.apply_config(test_source)

      assert_not_equal test_source, @manager.source('foo')
      assert_equal test_source, @manager.source('bar')
      assert_equal test_source, @manager.source('baz')
    end

    def test_callable_value_for_config_should_return_computed_value
      @manager.apply_config({ 'foo'          => 'bar',
                              'simple_value' => Proc.new { '666' },
                              'reference'    => Proc.new { self['foo'] } })

      assert_equal 'bar', @manager['foo']
      assert_equal '666', @manager['simple_value']
      assert_equal 'bar', @manager['reference']
    end

    def test_source_accessors_should_be_available_as_keys
      @manager.apply_config(TestSource.new)

      assert_equal 'some value', @manager['test_config_accessor']
    end

    def test_should_not_apply_removed_sources
      test_source = TestSource.new
      @manager.apply_config(test_source)
      @manager.remove_config(test_source)

      assert_equal nil, @manager['test_config_accessor']
    end

    class TestSource < ::Hash
      def test_config_accessor
        'some value'
      end
    end
  end
end
