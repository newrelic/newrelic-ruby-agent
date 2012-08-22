require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/configuration/manager'

module NewRelic::Agent::Configuration
  class ManagerTest < Test::Unit::TestCase
    def setup
      @manager = NewRelic::Agent::Configuration::Manager.new
    end

    def test_should_apply_config_sources_in_order
      config0 = {
        'foo' => 'default foo',
        'bar' => 'default bar',
        'baz' => 'default baz'
      }
      @manager.apply_config(config0)
      config1 = { 'foo' => 'real foo' }
      @manager.apply_config(config1)
      config2 = { 'foo' => 'wrong foo', 'bar' => 'real bar' }
      @manager.apply_config(config2, 1)

      assert_equal 'real foo', @manager['foo']
      assert_equal 'real bar', @manager['bar']
      assert_equal 'default baz', @manager['baz']

      @manager.remove_config(config0)
      @manager.remove_config(config1)
      @manager.remove_config(config2)
    end

    def test_identifying_config_source
      hash_source = {'foo' => 'foo', 'bar' => 'default'}
      @manager.apply_config(hash_source)
      test_source = TestSource.new
      test_source['bar'] = 'bar'
      test_source['baz'] = 'baz'
      @manager.apply_config(test_source)

      assert_not_equal test_source, @manager.source('foo')
      assert_equal test_source, @manager.source('bar')
      assert_equal test_source, @manager.source('baz')

      @manager.remove_config(hash_source)
      @manager.remove_config(test_source)
    end

    def test_callable_value_for_config_should_return_computed_value
      source = {
        'foo'          => 'bar',
        'simple_value' => Proc.new { '666' },
        'reference'    => Proc.new { self['foo'] }
      }
      @manager.apply_config(source)

      assert_equal 'bar', @manager['foo']
      assert_equal '666', @manager['simple_value']
      assert_equal 'bar', @manager['reference']

      @manager.remove_config(source)
    end

    def test_source_accessors_should_be_available_as_keys
      source = TestSource.new
      @manager.apply_config(source)

      assert_equal 'some value', @manager['test_config_accessor']

      @manager.remove_config(source)
    end

    def test_should_not_apply_removed_sources
      test_source = TestSource.new
      @manager.apply_config(test_source)
      @manager.remove_config(test_source)

      assert_equal nil, @manager['test_config_accessor']
    end

    def test_should_read_license_key_from_env
      ENV['NEWRELIC_LICENSE_KEY'] = 'right'
      manager = NewRelic::Agent::Configuration::Manager.new
      manager.apply_config({'license_key' => 'wrong'}, 1)

      assert_equal 'right', manager['license_key']
    end

    class TestSource < ::Hash
      def test_config_accessor
        'some value'
      end
    end
  end
end
