# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
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
      config1 = {:foo => 'wrong foo', :bar => 'real bar'}
      @manager.add_config_for_testing(config1)
      config2 = {:foo => 'real foo'}
      @manager.add_config_for_testing(config2)

      assert_equal 'real foo', @manager['foo']
      assert_equal 'real bar', @manager['bar']
      assert_equal 'default baz', @manager['baz']
    end

    def test_sources_applied_in_correct_order
      # in order of precedence
      high_security = HighSecuritySource.new({})
      server_source = ServerSource.new('data_report_period' => 3, 'capture_params' => true)
      manual_source = ManualSource.new(:data_report_period => 2, :bar => 'bar', :capture_params => true)

      # load them out of order, just to prove that load order
      # doesn't determine precedence
      @manager.replace_or_add_config(manual_source)
      @manager.replace_or_add_config(server_source)
      @manager.replace_or_add_config(high_security)

      assert_equal 3, @manager['data_report_period']
      assert_equal 'bar', @manager['bar']
      refute @manager['capture_params']
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
        :foo => 'bar',
        :simple_value => proc { '666' },
        :reference => proc { self['foo'] }
      }
      @manager.add_config_for_testing(source)

      assert_equal 'bar', @manager[:foo]
      assert_equal '666', @manager[:simple_value]
      assert_equal 'bar', @manager[:reference]
    end

    def test_manager_resolves_nested_procs_from_default_source
      source = {
        :foo => proc { self[:bar] },
        :bar => proc { self[:baz] },
        :baz => proc { 'Russian Nesting Dolls!' }
      }
      @manager.add_config_for_testing(source)

      source.keys.each do |key|
        assert_equal 'Russian Nesting Dolls!', @manager[key]
      end
    end

    def test_should_not_apply_removed_sources
      test_source = {:test_config_accessor => true}
      @manager.add_config_for_testing(test_source)
      @manager.remove_config(test_source)

      assert_nil @manager['test_config_accessor']
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

      @manager.instance_variable_get(:@configs_for_testing)
        .unshift(:setting => 'wrong value')

      assert_equal 'correct value', @manager[:setting]
    end

    def test_dotted_hash_to_hash_is_plain_hash
      dotted = NewRelic::Agent::Configuration::DottedHash.new({})

      assert_equal(::Hash, dotted.to_hash.class)
    end

    def test_to_collector_hash
      @manager.delete_all_configs_for_testing
      @manager.add_config_for_testing(:eins => proc { self[:one] })
      @manager.add_config_for_testing(:one => 1)
      @manager.add_config_for_testing(:two => 2)
      @manager.add_config_for_testing(:nested => {:madness => 'test'})
      @manager.add_config_for_testing(:'nested.madness' => 'test')

      assert_equal({:eins => 1, :one => 1, :two => 2, :'nested.madness' => 'test'},
        @manager.to_collector_hash)
    end

    # Necessary to keep the pruby marshaller happy
    def test_to_collector_hash_returns_bare_hash
      @manager.delete_all_configs_for_testing
      @manager.add_config_for_testing(:eins => proc { self[:one] })

      assert_equal(::Hash, @manager.to_collector_hash.class)
    end

    def test_to_collector_hash_scrubs_private_settings
      @manager.delete_all_configs_for_testing
      @manager.add_config_for_testing(:proxy_user => 'user')
      @manager.add_config_for_testing(:proxy_pass => 'password')
      @manager.add_config_for_testing(:one => 1)
      @manager.add_config_for_testing(:two => 2)

      assert_equal({:one => 1, :two => 2}, @manager.to_collector_hash)
    end

    def test_config_masks
      NewRelic::Agent::Configuration::MASK_DEFAULTS[:boo] = proc { true }

      @manager.add_config_for_testing(:boo => 1)

      refute @manager.to_collector_hash.has_key?(:boo)
    end

    def test_config_masks_conditionally
      NewRelic::Agent::Configuration::MASK_DEFAULTS[:boo] = proc { false }

      @manager.add_config_for_testing(:boo => 1)

      assert @manager.to_collector_hash.has_key?(:boo)
    end

    def test_config_masks_thread_profiler
      supported = NewRelic::Agent::Threading::BacktraceService.is_supported?
      reported_config = @manager.to_collector_hash

      if supported
        refute_nil reported_config[:'thread_profiler.enabled']
      else
        assert_nil reported_config[:'thread_profiler.enabled']
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

    def test_callback_evals_procs
      actual = nil
      @manager.register_callback(:test) do |value|
        actual = value
      end
      @manager.add_config_for_testing(:test => proc { 'value' })

      refute_equal actual.class, Proc, 'Callback returned Proc'
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
      @manager.add_config_for_testing(:layer => 'yo')

      refute_predicate @manager, :finished_configuring?

      @manager.replace_or_add_config(ServerSource.new({}))

      assert_predicate @manager, :finished_configuring?
    end

    def test_notifies_finished_configuring
      called = false
      NewRelic::Agent.instance.events.subscribe(:initial_configuration_complete) { called = true }
      @manager.replace_or_add_config(ServerSource.new({}))

      assert called
    end

    def test_doesnt_notify_unless_finished
      called = false
      NewRelic::Agent.instance.events.subscribe(:initial_configuration_complete) { called = true }

      @manager.add_config_for_testing(:fake => 'config')
      @manager.replace_or_add_config(ManualSource.new(:manual => true))
      @manager.replace_or_add_config(YamlSource.new('', 'test'))

      refute called
    end

    def test_high_security_enables_strip_exception_messages
      @manager.add_config_for_testing(:high_security => true)

      assert_truthy @manager[:'strip_exception_messages.enabled']
    end

    def test_stripped_exceptions_allowlist_contains_only_valid_exception_classes
      @manager.add_config_for_testing(:'strip_exception_messages.allowed_classes' => 'LocalJumpError, NonExistentException')

      assert_equal [LocalJumpError], @manager[:'strip_exception_messages.allowed_classes']
    end

    def test_should_log_when_applying
      log = with_array_logger(:debug) do
        @manager.add_config_for_testing(:test => 'asdf')
      end

      log_lines = log.array

      assert_match(/DEBUG.*asdf/, log_lines[0])
    end

    def test_should_log_when_removing
      config = {:test => 'asdf'}
      @manager.add_config_for_testing(config)

      log = with_array_logger(:debug) do
        @manager.remove_config(config)
      end

      log_lines = log.array

      refute_match(/DEBUG.*Config Stack.*asdf/, log_lines[0])
    end

    def test_config_is_correctly_initialized
      assert_includes(@manager.config_classes_for_testing, EnvironmentSource)
      assert_includes(@manager.config_classes_for_testing, DefaultSource)
      refute_includes @manager.config_classes_for_testing, ManualSource
      refute_includes @manager.config_classes_for_testing, ServerSource
      refute_includes @manager.config_classes_for_testing, YamlSource
      refute_includes @manager.config_classes_for_testing, HighSecuritySource
    end

    load_cross_agent_test('labels').each do |testcase|
      define_method("test_#{testcase['name']}") do
        @manager.add_config_for_testing(:labels => testcase['labelString'])

        assert_warning if testcase['warning']

        assert_equal(testcase['expected'].sort_by { |h| h['label_type'] },
          @manager.parse_labels_from_string.sort_by { |h| h['label_type'] },
          "failed on #{testcase['name']}")
      end
    end

    def test_parse_labels_from_dictionary_with_hard_failure
      bad_label_object = Object.new
      @manager.add_config_for_testing(:labels => bad_label_object)

      assert_parsing_error
      assert_parsed_labels([])
    end

    def test_parse_labels_from_string_with_hard_failure
      bad_string = +'baaaad'
      bad_string.stubs(:strip).raises('Booom')
      @manager.add_config_for_testing(:labels => bad_string)

      assert_parsing_error
      assert_parsed_labels([])
    end

    def test_parse_labels_from_dictionary
      @manager.add_config_for_testing(:labels => {'Server' => 'East', 'Data Center' => 'North'})

      assert_parsed_labels([
        {'label_type' => 'Server', 'label_value' => 'East'},
        {'label_type' => 'Data Center', 'label_value' => 'North'}
      ])
    end

    def test_parse_labels_from_dictionary_applies_length_limits
      @manager.add_config_for_testing(:labels => {'K' * 256 => 'V' * 256})
      expected = [{'label_type' => 'K' * 255, 'label_value' => 'V' * 255}]

      expects_logging(:warn, includes('truncated'))

      assert_parsed_labels(expected)
    end

    def test_parse_labels_from_dictionary_disallows_further_nested_hashes
      @manager.add_config_for_testing(:labels => {
        'More Nesting' => {'Hahaha' => 'Ha'}
      })

      assert_warning
      assert_parsed_labels([])
    end

    def test_parse_labels_from_dictionary_allows_numerics
      @manager.add_config_for_testing(:labels => {
        'the answer' => 42
      })

      expected = [{'label_type' => 'the answer', 'label_value' => '42'}]

      assert_parsed_labels(expected)
    end

    def test_parse_labels_from_dictionary_allows_booleans
      @manager.add_config_for_testing(:labels => {
        'truthy' => true,
        'falsy' => false
      })

      expected = [
        {'label_type' => 'truthy', 'label_value' => 'true'},
        {'label_type' => 'falsy', 'label_value' => 'false'}
      ]

      assert_parsed_labels(expected)
    end

    def test_apply_transformations
      transform = proc { |value| value.gsub('foo', 'baz') }
      ::NewRelic::Agent::Configuration::DefaultSource.stubs(:transform_for).returns(transform)

      assert_equal 'bazbar', @manager.apply_transformations(:test, 'foobar')
    end

    def test_fetch_with_a_transform_returns_the_transformed_value
      with_config(:rules => {:ignore_url_regexes => ['more than meets the eye']}) do
        assert_equal [/more than meets the eye/], @manager.fetch(:'rules.ignore_url_regexes')
      end
    end

    def test_prepend_key_absent_to_instrumentation_value_of
      with_config({}) do
        result = @manager.fetch(:'instrumentation.net_http')

        assert_equal 'auto', result
      end
    end

    def test_prepend_key_true_to_instrumentation_value_of
      with_config(:prepend_net_instrumentation => true) do
        result = @manager.fetch(:'instrumentation.net_http')

        assert_equal 'auto', result
      end
    end

    def test_default_to_value_of
      with_config(:'transaction_tracer.record_sql' => 'raw') do
        result = @manager.fetch(:'slow_sql.record_sql')

        assert_equal('raw', result)
      end
    end

    def test_default_to_value_of_only_happens_at_defaults
      with_config(:'transaction_tracer.record_sql' => 'raw', :'slow_sql.record_sql' => 'none') do
        result = @manager.fetch(:'slow_sql.record_sql')

        assert_equal('none', result)
      end
    end

    def test_apply_transformations_logs_warning_if_transformation_fails
      key = :test_key
      bomb = proc { raise 'kaboom' }
      ds = Minitest::Mock.new
      ds.expect :transform_for, bomb, [key]
      @manager.stubs(:default_source).returns(ds)
      expects_logging(:warn, includes('Error encountered while applying transformation'), any_parameters)
      @manager.apply_transformations(key, 'test_value')
      ds.verify
    end

    def test_auto_determined_values_stay_cached
      with_config(:'security.agent.enabled' => true) do
        name = :knockbreck_manse

        DependencyDetection.defer do
          named(name)
          executes { use_prepend? }
        end

        key = :"instrumentation.#{name}"
        with_config(key => 'auto') do
          DependencyDetection.detect!

          @manager.replace_or_add_config(ServerSource.new({}))

          assert_equal :prepend, @manager.instance_variable_get(:@cache)[key]
        end
      end
    end

    def test_unsatisfied_values_stay_cached
      name = :tears_of_the_kingdom

      DependencyDetection.defer do
        named(name)

        # guarantee the instrumentation's dependencies are unsatisfied
        depends_on { return false }
        executes { use_prepend? }
      end

      key = :"instrumentation.#{name}"
      with_config(key => 'prepend') do
        DependencyDetection.detect!

        @manager.replace_or_add_config(ServerSource.new({}))

        assert_equal :unsatisfied, @manager.instance_variable_get(:@cache)[key]
      end
    end

    def test_logger_does_not_receive_excluded_settings
      log = with_array_logger(:debug) { @manager.log_config('direction', ManualSource.new({})) }.array.join('')

      assert_includes(log, 'app_name')
      refute_includes(log, 'license_key')
    end

    def test_reset_cache_return_early_for_jruby
      phony_cache = {dup_called: false}
      def phony_cache.dup; self[:dup_called] = true; self; end
      @manager.instance_variable_set(:@cache, phony_cache)
      NewRelic::LanguageSupport.stub :jruby?, true do
        @manager.reset_cache
      end

      refute phony_cache[:dup_called], 'Expected the use of JRuby to prevent the Hash#dup call!'
    ensure
      @manager.new_cache
    end

    # https://github.com/newrelic/newrelic-ruby-agent/issues/2919
    def test_that_boolean_based_params_always_go_through_any_defined_transform_sequence
      key = :soundwave
      defaults = {key => {default: false,
                          public: true,
                          type: Boolean,
                          allowed_from_server: false,
                          transform: proc { |bool| bool.to_s.reverse },
                          description: 'Param what transforms'}}
      NewRelic::Agent::Configuration.stub_const(:DEFAULTS, defaults) do
        mgr = NewRelic::Agent::Configuration::Manager.new
        value = mgr[key]

        assert_equal 'eslaf', value, 'Expected `false` boolean value to be transformed!'
      end
    end

    def test_type_coercion_of_an_integer_from_a_string
      key = :max_chocolate_chips
      defaults = {key => {default: 0, type: Integer}}
      NewRelic::Agent::Configuration::Manager.stub_const(:DEFAULTS, defaults) do
        value = @manager.type_coerce(key, '1138', :manual)

        assert_equal 1138, value
      end
    end

    def test_type_coercion_of_a_float_from_a_string
      key = :slice_dice_ratio
      defaults = {key => {default: 0.0, type: Float}}
      NewRelic::Agent::Configuration::Manager.stub_const(:DEFAULTS, defaults) do
        value = @manager.type_coerce(key, '867.5309', :manual)

        assert_equal 867.5309, value # rubocop:disable Minitest/AssertInDelta
      end
    end

    def test_type_coercion_of_a_string_from_a_symbol
      key = :alert_highlight_color
      defaults = {key => {default: 'beige', type: String}}
      NewRelic::Agent::Configuration::Manager.stub_const(:DEFAULTS, defaults) do
        value = @manager.type_coerce(key, :'forest green', :manual)

        assert_equal 'forest green', value
      end
    end

    def test_type_coercion_of_a_symbol_from_a_string
      key = :sampling_direction
      defaults = {key => {default: :forwards, type: Symbol}}
      NewRelic::Agent::Configuration::Manager.stub_const(:DEFAULTS, defaults) do
        value = @manager.type_coerce(key, 'backwards', :manual)

        assert_equal :backwards, value
      end
    end

    def test_type_coercion_of_an_array_from_a_string
      key = :allowlisted_job_params
      defaults = {key => {default: [], type: Array}}
      NewRelic::Agent::Configuration::Manager.stub_const(:DEFAULTS, defaults) do
        value = @manager.type_coerce(key, 'beans, rice, cheese', :manual)

        assert_equal %w[beans rice cheese], value
      end
    end

    def test_type_coercion_of_a_hash_from_a_string
      key = :id_map
      defaults = {key => {default: {}, type: Hash}}
      NewRelic::Agent::Configuration::Manager.stub_const(:DEFAULTS, defaults) do
        value = @manager.type_coerce(key, '19 = 81, Blind = Chance', :manual)

        assert_equal({'19' => '81', 'Blind' => 'Chance'}, value)
      end
    end

    def test_type_coercion_of_a_boolean_from_a_string
      key = :vm_performance_analysis
      defaults = {key => {default: false, type: NewRelic::Agent::Configuration::Boolean}}
      NewRelic::Agent::Configuration::Manager.stub_const(:DEFAULTS, defaults) do
        value = @manager.type_coerce(key, 'on', :manual)

        assert_equal true, value # rubocop:disable Minitest/AssertTruthy
      end
    end

    def test_type_coercion_of_an_integer_from_a_float
      key = :applied_jigawatts
      defaults = {key => {default: 0, type: Integer}}
      NewRelic::Agent::Configuration::Manager.stub_const(:DEFAULTS, defaults) do
        value = @manager.type_coerce(key, 1.21, :manual)

        assert_equal 1, value
      end
    end

    def test_type_coercion_of_a_float_from_an_int
      key = :refresh_sampling_ratio
      defaults = {key => {default: 12.5, type: Float}}
      NewRelic::Agent::Configuration::Manager.stub_const(:DEFAULTS, defaults) do
        value = @manager.type_coerce(key, 25, :manual)

        assert_equal 25.0, value # rubocop:disable Minitest/AssertInDelta
      end
    end

    def test_type_coercion_rejects_invalid_input_and_falls_back_to_the_default
      key = :error_rate_threshold
      default = 50
      defaults = {key => {default: default, type: Integer}}
      NewRelic::Agent::Configuration::Manager.stub_const(:DEFAULTS, defaults) do
        expects_logging(:warn, includes('Expected to receive a value of type Integer matching pattern '))

        value = @manager.type_coerce(key, 'seventy-five', :manual)

        assert_equal default, value
      end
    end

    def test_type_coercion_anticipates_an_invalid_type_without_a_proc_defined
      key = :unexpected
      input = 'original'
      defaults = {key => {default: nil, type: Class}}
      NewRelic::Agent::Configuration::Manager.stub_const(:DEFAULTS, defaults) do
        value = @manager.type_coerce(key, input, :manual)

        assert_equal input, value
      end
    end

    def test_add_config_for_testing_enforces_an_input_class_allowlist
      error = assert_raises RuntimeError do
        @manager.add_config_for_testing(nil)
      end

      assert_equal 'Invalid config type for testing', error.message
    end

    def test_validate_nil_expects_nils_from_tests
      expects_no_logging(:warn)

      refute @manager.validate_nil(:a_key, :test)
    end

    def test_validates_nil_allows_nil_if_the_config_param_has_allow_nil_set
      key = :optional_tolerance
      defaults = {key => {default: '', type: String, allow_nil: true}}
      NewRelic::Agent::Configuration::Manager.stub_const(:DEFAULTS, defaults) do
        expects_no_logging(:warn)

        refute @manager.validate_nil(key, :nr)
      end
    end

    def test_validate_nil_warns_users
      key = :required_tolerance
      default = 1138
      defaults = {key => {default: default, type: String}}
      NewRelic::Agent::Configuration::Manager.stub_const(:DEFAULTS, defaults) do
        expects_logging(:warn, includes('Nil values are not permitted'))

        value = @manager.validate_nil(key, :user)

        assert_equal default, value
      end
    end

    def test_validate_nil_does_not_warn_for_nr_internal_category
      key = :required_tolerance
      default = 1138
      defaults = {key => {default: default, type: String}}
      NewRelic::Agent::Configuration::Manager.stub_const(:DEFAULTS, defaults) do
        expects_no_logging(:warn)

        value = @manager.validate_nil(key, :nr)

        assert_equal default, value
      end
    end

    def test_enforce_allowlist_only_operates_on_params_with_allowlists
      key = :unguarded

      default_source = Object.new
      # Use block to ensure reliable stubbing - always return nil
      default_source.stubs(:allowlist_for) { |_k| nil }
      @manager.stubs(:default_source).returns(default_source)

      expects_no_logging(:warn)

      value = @manager.enforce_allowlist(key, 9)

      assert_equal 9, value
    end

    def test_enforce_allowlist_does_not_warn_if_the_input_value_is_on_the_allowlist
      key = :guarded
      default = 1138
      allowlist = [default, 11, 38]
      defaults = {key => {default: default, allowlist: allowlist}}

      default_source = Object.new
      # Use block to ensure reliable stubbing - return allowlist only for test key
      default_source.stubs(:allowlist_for) { |k| k == key ? allowlist : nil }
      @manager.stubs(:default_source).returns(default_source)

      NewRelic::Agent::Configuration::Manager.stub_const(:DEFAULTS, defaults) do
        expects_no_logging(:warn)

        value = @manager.enforce_allowlist(key, 11)

        assert_equal 11, value
      end
    end

    def test_enforce_allowlist_warns_if_the_input_value_is_not_on_the_allowlist
      key = :guarded
      default = 1138
      allowlist = [default, 11, 38]
      defaults = {key => {default: default, allowlist: allowlist}}

      default_source = Object.new
      # Prevent JRuby mock pollution by being specific about which key gets which allowlist
      default_source.stubs(:allowlist_for).returns(nil)  # Return nil for other keys like security.agent.enabled
      default_source.stubs(:allowlist_for).with(key).returns(allowlist)
      @manager.stubs(:default_source).returns(default_source)

      NewRelic::Agent::Configuration::Manager.stub_const(:DEFAULTS, defaults) do
        expects_logging(:warn, includes('Expected to receive a value found on the following list'))

        value = @manager.enforce_allowlist(key, 9)

        assert_equal default, value
      end
    end

    private

    def assert_parsed_labels(expected)
      result = @manager.parsed_labels

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
