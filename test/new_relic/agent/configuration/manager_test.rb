# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/configuration/manager'
require 'new_relic/agent/configuration/mask_defaults'
require 'new_relic/agent/threading/backtrace_service'

module NewRelic::Agent::Configuration
  class ManagerTest < Minitest::Test
    def setup
      # Defaults look up against the shared config, so reset and use it
      NewRelic::Agent.reset_config
      @manager = NewRelic::Agent.config
    end

    def teardown
      @manager.reset_to_defaults
    end

    def test_should_use_indifferent_access
      config = NewRelic::Agent::Configuration::DottedHash.new('string' => 'string', :symbol => 'symbol')
      @manager.add_config_for_testing(config)
      assert_equal 'string', @manager[:string]
      assert_equal 'symbol', @manager['symbol']
    end

    def test_should_apply_config_sources_in_order
      config0 = {
        :foo => 'default foo',
        :bar => 'default bar',
        :baz => 'default baz'
      }
      @manager.add_config_for_testing(config0, false)
      config1 = { :foo => 'wrong foo', :bar => 'real bar' }
      @manager.add_config_for_testing(config1)
      config2 = { :foo => 'real foo' }
      @manager.add_config_for_testing(config2)

      assert_equal 'real foo'   , @manager['foo']
      assert_equal 'real bar'   , @manager['bar']
      assert_equal 'default baz', @manager['baz']
    end

    def test_sources_applied_in_correct_order
      # in order of precedence
      high_security = HighSecuritySource.new({})
      server_source = ServerSource.new(:foo => 'foo', :capture_params => true)
      manual_source = ManualSource.new(:foo => 'bad', :bar => 'bar',
                                       :capture_params => true)

      # load them out of order, just to prove that load order
      # doesn't determine precedence
      @manager.replace_or_add_config(manual_source)
      @manager.replace_or_add_config(server_source)
      @manager.replace_or_add_config(high_security)

      assert_equal 'foo', @manager['foo']
      assert_equal 'bar', @manager['bar']
      assert_equal false, @manager['capture_params']
    end

    def test_identifying_config_source
      hash_source = {:foo => 'foo', :bar => 'default'}
      @manager.add_config_for_testing(hash_source, false)
      test_source = ManualSource.new(:bar => 'bar', :baz => 'baz')
      @manager.replace_or_add_config(test_source)

      refute_equal test_source, @manager.source(:foo)
      assert_equal test_source, @manager.source(:bar)
      assert_equal test_source, @manager.source(:baz)
    end

    def test_callable_value_for_config_should_return_computed_value
      source = {
        :foo          => 'bar',
        :simple_value => Proc.new { '666' },
        :reference    => Proc.new { self['foo'] }
      }
      @manager.add_config_for_testing(source)

      assert_equal 'bar', @manager[:foo]
      assert_equal '666', @manager[:simple_value]
      assert_equal 'bar', @manager[:reference]
    end

    def test_manager_resolves_nested_procs_from_default_source
      source = {
        :foo    => Proc.new { self[:bar] },
        :bar    => Proc.new { self[:baz] },
        :baz    => Proc.new { 'Russian Nesting Dolls!' }
      }
      @manager.add_config_for_testing(source)

      source.keys.each do |key|
        assert_equal 'Russian Nesting Dolls!', @manager[key]
      end
    end

    def test_should_not_apply_removed_sources
      test_source = { :test_config_accessor => true }
      @manager.add_config_for_testing(test_source)
      @manager.remove_config(test_source)

      assert_equal nil, @manager['test_config_accessor']
    end

    def test_should_read_license_key_from_env
      ENV['NEWRELIC_LICENSE_KEY'] = 'right'
      manager = NewRelic::Agent::Configuration::Manager.new
      manager.add_config_for_testing({:license_key => 'wrong'}, false)

      assert_equal 'right', manager['license_key']
    ensure
      ENV.delete('NEWRELIC_LICENSE_KEY')
    end

    def test_config_values_should_be_memoized
      @manager.add_config_for_testing(:setting => 'correct value')
      assert_equal 'correct value', @manager[:setting]

      @manager.instance_variable_get(:@configs_for_testing).
               unshift(:setting => 'wrong value')

      assert_equal 'correct value', @manager[:setting]
    end

    def test_dotted_hash_to_hash_is_plain_hash
      dotted = NewRelic::Agent::Configuration::DottedHash.new({})
      assert_equal(::Hash, dotted.to_hash.class)
    end

    def test_to_collector_hash
      @manager.delete_all_configs_for_testing
      @manager.add_config_for_testing(:eins => Proc.new { self[:one] })
      @manager.add_config_for_testing(:one => 1)
      @manager.add_config_for_testing(:two => 2)
      @manager.add_config_for_testing(:nested => {:madness => 'test'})
      @manager.add_config_for_testing(:'nested.madness' => 'test')

      assert_equal({ :eins => 1, :one => 1, :two => 2, :'nested.madness' => 'test' },
                   @manager.to_collector_hash)
    end

    # Necessary to keep the pruby marshaller happy
    def test_to_collector_hash_returns_bare_hash
      @manager.delete_all_configs_for_testing
      @manager.add_config_for_testing(:eins => Proc.new { self[:one] })

      assert_equal(::Hash, @manager.to_collector_hash.class)
    end

    def test_to_collector_hash_scrubs_private_settings
      @manager.delete_all_configs_for_testing
      @manager.add_config_for_testing(:proxy_user => 'user')
      @manager.add_config_for_testing(:proxy_pass => 'password')
      @manager.add_config_for_testing(:one => 1)
      @manager.add_config_for_testing(:two => 2)

      assert_equal({ :one => 1, :two => 2 }, @manager.to_collector_hash)
    end

    def test_config_masks
      NewRelic::Agent::Configuration::MASK_DEFAULTS[:boo] = Proc.new { true }

      @manager.add_config_for_testing(:boo => 1)

      assert_equal false, @manager.to_collector_hash.has_key?(:boo)
    end

    def test_config_masks_conditionally
      NewRelic::Agent::Configuration::MASK_DEFAULTS[:boo] = Proc.new { false }

      @manager.add_config_for_testing(:boo => 1)

      assert @manager.to_collector_hash.has_key?(:boo)
    end

    def test_config_masks_thread_profiler
      supported = NewRelic::Agent::Threading::BacktraceService.is_supported?
      reported_config = @manager.to_collector_hash

      if supported
        refute_nil reported_config[:'thread_profiler.enabled']
      else
        assert_equal nil, reported_config[:'thread_profiler.enabled']
      end
    end

    def test_replacing_a_layer_by_class
      old_config = NewRelic::Agent::Configuration::ManualSource.new(:test => 'wrong')
      @manager.replace_or_add_config(old_config)
      new_config = NewRelic::Agent::Configuration::ManualSource.new(:test => 'right')
      @manager.replace_or_add_config(new_config)

      assert_equal 'right', @manager[:test]
      assert_equal 3, @manager.num_configs_for_testing
    end

    def test_registering_a_callback
      observed_value = 'old'
      @manager.add_config_for_testing(:test => 'original')

      @manager.register_callback(:test) do |value|
        observed_value = value
      end
      assert_equal 'original', observed_value

      @manager.add_config_for_testing(:test => 'new')
      assert_equal 'new', observed_value
    end

    def test_callback_not_called_if_no_change
      state = nil
      @manager.add_config_for_testing(:test => true, :other => false)
      @manager.register_callback(:test) do |value|
        state = 'wrong'
      end
      state = 'right'
      config = {:test => true}
      @manager.add_config_for_testing(config)
      @manager.remove_config(config)

      assert_equal 'right', state
    end

    def test_finished_configuring
      @manager.add_config_for_testing(:layer => "yo")
      assert_equal false, @manager.finished_configuring?

      @manager.replace_or_add_config(ServerSource.new({}))
      assert_equal true, @manager.finished_configuring?
    end

    def test_notifies_finished_configuring
      called = false
      NewRelic::Agent.instance.events.subscribe(:finished_configuring) { called = true }
      @manager.replace_or_add_config(ServerSource.new({}))

      assert_equal true, called
    end

    def test_doesnt_notify_unless_finished
      called = false
      NewRelic::Agent.instance.events.subscribe(:finished_configuring) { called = true }

      @manager.add_config_for_testing(:fake => "config")
      @manager.replace_or_add_config(ManualSource.new(:manual => true))
      @manager.replace_or_add_config(YamlSource.new("", "test"))

      assert_equal false, called
    end

    def test_high_security_enables_strip_exception_messages
      @manager.add_config_for_testing(:high_security => true)

      assert_truthy @manager[:'strip_exception_messages.enabled']
    end

    def test_stripped_exceptions_whitelist_contains_only_valid_exception_classes
      @manager.add_config_for_testing(:'strip_exception_messages.whitelist' => 'LocalJumpError, NonExistentException')
      assert_equal [LocalJumpError], @manager.stripped_exceptions_whitelist
    end

    def test_should_log_when_applying
      log = with_array_logger(:debug) do
        @manager.add_config_for_testing(:test => "asdf")
      end

      log_lines = log.array
      assert_match(/DEBUG.*asdf/, log_lines[0])
    end

    def test_should_log_when_removing
      config = { :test => "asdf" }
      @manager.add_config_for_testing(config)

      log = with_array_logger(:debug) do
        @manager.remove_config(config)
      end

      log_lines = log.array
      refute_match(/DEBUG.*asdf/, log_lines[0])
    end

    def test_config_is_correctly_initialized
      assert @manager.config_classes_for_testing.include?(EnvironmentSource)
      assert @manager.config_classes_for_testing.include?(DefaultSource)
      refute @manager.config_classes_for_testing.include?(ManualSource)
      refute @manager.config_classes_for_testing.include?(ServerSource)
      refute @manager.config_classes_for_testing.include?(YamlSource)
      refute @manager.config_classes_for_testing.include?(HighSecuritySource)
    end

    load_cross_agent_test("labels").each do |testcase|
      define_method("test_#{testcase['name']}") do
        @manager.add_config_for_testing(:labels => testcase["labelString"])

        assert_warning if testcase["warning"]
        assert_equal(testcase["expected"], @manager.parse_labels_from_string)
      end
    end

    def test_parse_labels_from_dictionary_with_hard_failure
      bad_label_object = Object.new
      @manager.add_config_for_testing(:labels => bad_label_object)

      assert_parsing_error
      assert_parsed_labels([])
    end

    def test_parse_labels_from_string_with_hard_failure
      bad_string = "baaaad"
      bad_string.stubs(:gsub).raises("Booom")
      @manager.add_config_for_testing(:labels => bad_string)

      assert_parsing_error
      assert_parsed_labels([])
    end

    def test_parse_labels_from_dictionary
      @manager.add_config_for_testing(:labels => { 'Server' => 'East', 'Data Center' => 'North' })

      assert_parsed_labels([
        { 'label_type' => 'Server', 'label_value' => 'East' },
        { 'label_type' => 'Data Center', 'label_value' => 'North' }
      ])
    end

    def test_parse_labels_from_dictionary_applies_length_limits
      @manager.add_config_for_testing(:labels => { 'K' * 256 => 'V' * 256 })
      expected = [ { 'label_type' => 'K' * 255, 'label_value' => 'V' * 255 } ]

      expects_logging(:warn, includes("truncated"))
      assert_parsed_labels(expected)
    end

    def test_parse_labels_from_dictionary_disallows_further_nested_hashes
      @manager.add_config_for_testing(:labels => {
        "More Nesting" => { "Hahaha" => "Ha" }
      })

      assert_warning
      assert_parsed_labels([])
    end

    def test_parse_labels_from_dictionary_allows_numerics
      @manager.add_config_for_testing(:labels => {
        "the answer" => 42
      })

      expected = [{ 'label_type' => 'the answer', 'label_value' => '42' }]
      assert_parsed_labels(expected)
    end

    def test_parse_labels_from_dictionary_allows_booleans
      @manager.add_config_for_testing(:labels => {
        "truthy" => true,
        "falsy"  => false
      })

      expected = [
        { 'label_type' => 'truthy', 'label_value' => 'true' },
        { 'label_type' => 'falsy',  'label_value' => 'false' }
      ]
      assert_parsed_labels(expected)
    end

    def assert_parsed_labels(expected)
      result = @manager.parsed_labels

      # 1.8.7 hash ordering means we can't directly compare. Lean on the
      # structure and flattened array sorting to do the comparison we need.
      result = result.map(&:to_a).sort
      expected = expected.map(&:to_a).sort

      assert_equal expected, result
    end

    def assert_warning
      expects_logging(:warn, any_parameters, any_parameters)
    end

    def assert_parsing_error
      expects_logging(:error, includes(Manager::PARSING_LABELS_FAILURE), any_parameters)
    end
  end
end
