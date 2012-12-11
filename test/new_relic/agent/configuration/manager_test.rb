require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/configuration/manager'

module NewRelic::Agent::Configuration
  class ManagerTest < Test::Unit::TestCase
    def setup
      @manager = NewRelic::Agent::Configuration::Manager.new
    end

    def test_should_use_indifferent_access
      config = NewRelic::Agent::Configuration::DottedHash.new('string' => 'string', :symbol => 'symbol')
      @manager.apply_config(config)
      assert_equal 'string', @manager[:string]
      assert_equal 'symbol', @manager['symbol']
      @manager.remove_config(config)
    end

    def test_should_apply_config_sources_in_order
      config0 = {
        :foo => 'default foo',
        :bar => 'default bar',
        :baz => 'default baz'
      }
      @manager.apply_config(config0)
      config1 = { :foo => 'real foo' }
      @manager.apply_config(config1)
      config2 = { :foo => 'wrong foo', :bar => 'real bar' }
      @manager.apply_config(config2, 1)

      assert_equal 'real foo', @manager['foo']
      assert_equal 'real bar', @manager['bar']
      assert_equal 'default baz', @manager['baz']

      @manager.remove_config(config0)
      @manager.remove_config(config1)
      @manager.remove_config(config2)
    end

    def test_identifying_config_source
      hash_source = {:foo => 'foo', :bar => 'default'}
      @manager.apply_config(hash_source)
      test_source = TestSource.new
      test_source[:bar] = 'bar'
      test_source[:baz] = 'baz'
      @manager.apply_config(test_source)

      assert_not_equal test_source, @manager.source(:foo)
      assert_equal test_source, @manager.source(:bar)
      assert_equal test_source, @manager.source(:baz)

      @manager.remove_config(hash_source)
      @manager.remove_config(test_source)
    end

    def test_callable_value_for_config_should_return_computed_value
      source = {
        :foo          => 'bar',
        :simple_value => Proc.new { '666' },
        :reference    => Proc.new { self['foo'] }
      }
      @manager.apply_config(source)

      assert_equal 'bar', @manager[:foo]
      assert_equal '666', @manager[:simple_value]
      assert_equal 'bar', @manager[:reference]

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
      manager.apply_config({:license_key => 'wrong'}, 1)

      assert_equal 'right', manager['license_key']
    end

    def test_config_values_should_be_memoized
      @manager.apply_config(:setting => 'correct value')
      assert_equal 'correct value', @manager[:setting]

      @manager.config_stack.unshift(:setting => 'wrong value')
      assert_equal 'correct value', @manager[:setting]
    end

    def test_flattened_config
      @manager.instance_variable_set(:@config_stack, [])
      @manager.apply_config(:eins => Proc.new { self[:one] })
      @manager.apply_config(:one => 1)
      @manager.apply_config(:two => 2)
      @manager.apply_config(:three => 3)

      assert_equal({ :eins => 1, :one => 1, :two => 2, :three => 3 },
                   @manager.flattened_config)
    end

    def test_replacing_a_layer_by_class
      old_config = NewRelic::Agent::Configuration::ManualSource.new(:test => 'wrong')
      @manager.apply_config(old_config, 1)
      new_config = NewRelic::Agent::Configuration::ManualSource.new(:test => 'right')
      @manager.replace_or_add_config(new_config)

      assert_equal 'right', @manager[:test]
      assert_equal 3, @manager.config_stack.size
      assert_equal 1, @manager.config_stack.map{|s| s.class} \
        .index(NewRelic::Agent::Configuration::ManualSource)
    end

    def test_registering_a_callback
      observed_value = 'old'
      @manager.apply_config(:test => 'original')

      @manager.register_callback(:test) do |value|
        observed_value = value
      end
      assert_equal 'original', observed_value

      @manager.apply_config(:test => 'new')
      assert_equal 'new', observed_value
    end

    def test_callback_not_called_if_no_change
      @manager.apply_config(:test => true, :other => false)
      @manager.register_callback(:test) do |value|
        state = 'wrong'
      end
      state = 'right'
      config = {:test => true}
      @manager.apply_config(config)
      @manager.remove_config(config)

      assert_equal 'right', state
    end

    class TestSource < ::Hash
      def test_config_accessor
        'some value'
      end
    end
  end
end
