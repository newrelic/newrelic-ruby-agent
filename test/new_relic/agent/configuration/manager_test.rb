# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/configuration/manager'
require 'new_relic/agent/configuration/mask_defaults'
require 'new_relic/agent/threading/backtrace_service'

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

    def test_manager_resolves_nested_procs_from_default_source
      source = {
        :foo    => Proc.new { self[:bar] },
        :bar    => Proc.new { self[:baz] },
        :baz    => Proc.new { 'Russian Nesting Dolls!' }
      }
      @manager.apply_config(source)

      source.keys.each do |key|
        assert_equal 'Russian Nesting Dolls!', @manager[key]
      end

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

    def test_dotted_hash_to_hash_is_plain_hash
      dotted = NewRelic::Agent::Configuration::DottedHash.new({})
      assert_equal(::Hash, dotted.to_hash.class)
    end

    def test_to_collector_hash
      @manager.instance_variable_set(:@config_stack, [])
      @manager.apply_config(:eins => Proc.new { self[:one] })
      @manager.apply_config(:one => 1)
      @manager.apply_config(:two => 2)
      @manager.apply_config(:nested => {:madness => 'test'})
      @manager.apply_config(:'nested.madness' => 'test')

      assert_equal({ :eins => 1, :one => 1, :two => 2, :'nested.madness' => 'test' },
                   @manager.to_collector_hash)
    end

    # Necessary to keep the pruby marshaller happy
    def test_to_collector_hash_returns_bare_hash
      @manager.instance_variable_set(:@config_stack, [])
      @manager.apply_config(:eins => Proc.new { self[:one] })

      assert_equal(::Hash, @manager.to_collector_hash.class)
    end

    def test_config_masks
      NewRelic::Agent::Configuration::MASK_DEFAULTS[:boo] = Proc.new { true }

      @manager.apply_config(:boo => 1)

      assert_equal false, @manager.to_collector_hash.has_key?(:boo)
    end

    def test_config_masks_conditionally
      NewRelic::Agent::Configuration::MASK_DEFAULTS[:boo] = Proc.new { false }

      @manager.apply_config(:boo => 1)

      assert @manager.to_collector_hash.has_key?(:boo)
    end

    def test_config_masks_thread_profiler
      supported = NewRelic::Agent::Threading::BacktraceService.is_supported?
      reported_config = @manager.to_collector_hash

      if supported
        assert_not_nil reported_config[:'thread_profiler.enabled']
      else
        assert_equal nil, reported_config[:'thread_profiler.enabled']
      end
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

    def test_finished_configuring
      @manager.apply_config(:layer => "yo")
      assert_equal false, @manager.finished_configuring?

      @manager.apply_config(ServerSource.new({}))
      assert_equal true, @manager.finished_configuring?
    end

    def test_notifies_finished_configuring
      called = false
      NewRelic::Agent.instance.events.subscribe(:finished_configuring) { called = true }
      @manager.apply_config(ServerSource.new({}))

      assert_equal true, called
    end

    def test_doesnt_notify_unless_finished
      called = false
      NewRelic::Agent.instance.events.subscribe(:finished_configuring) { called = true }

      @manager.apply_config(:fake => "config")
      @manager.apply_config(ManualSource.new(:manual => true))
      @manager.apply_config(YamlSource.new("", "test"))

      assert_equal false, called
    end

    def test_high_security_enables_strip_exception_messages
      @manager.apply_config(:high_security => true)

      assert_truthy @manager[:'strip_exception_messages.enabled']
    end

    def test_stripped_exceptions_whitelist_contains_only_valid_exception_classes
      @manager.apply_config(:'strip_exception_messages.whitelist' => 'LocalJumpError, NonExistentException')
      assert_equal [LocalJumpError], @manager.stripped_exceptions_whitelist
    end

    def test_should_log_when_applying
      expects_logging(:debug, anything, includes("asdf"))
      @manager.apply_config(:test => "asdf")
    end

    def test_should_log_when_removing
      config = { :test => "asdf" }
      @manager.apply_config(config)

      expects_logging(:debug, anything, Not(includes("asdf")))
      @manager.remove_config(config)
    end

    class TestSource < ::Hash
      def test_config_accessor
        'some value'
      end
    end
  end
end
