# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'

module ::The
  class Example
    def self.class_method; end
    def instance_method; end
    private # rubocop:disable Layout/EmptyLinesAroundAccessModifier
    def private_method; end
  end
end

class NewRelic::Agent::MethodTracerHelpersTest < Minitest::Test
  # No assert. This test helps increase branch coverage.
  def test_trace_execution_scoped_not_traced
    in_transaction do
      NewRelic::Agent::Tracer.state.untraced << false
      NewRelic::Agent::MethodTracerHelpers.trace_execution_scoped('cats') { 'a block' }
    end
  end

  def test_obtains_a_class_name_from_a_singleton_class_string
    with_config(:'code_level_metrics.enabled' => true) do
      name = NewRelic::Agent::MethodTracerHelpers.send(:klass_name, The::Example.singleton_class.to_s)

      assert_equal 'The::Example', name
    end
  end

  def test_returns_nil_if_a_name_cannot_be_determined
    with_config(:'code_level_metrics.enabled' => true) do
      assert_raises RuntimeError do
        NewRelic::Agent::MethodTracerHelpers.send(:klass_name, 'StrawberriesAndSashimi')
      end
    end
  end

  def test_gets_at_an_underlying_class_from_a_singleton_class
    with_config(:'code_level_metrics.enabled' => true) do
      klass = NewRelic::Agent::MethodTracerHelpers.send(:klassify_singleton, The::Example.singleton_class)

      assert_equal klass, The::Example
    end
  end

  def test_do_not_gather_code_info_when_disabled_by_configuration
    with_config(:'code_level_metrics.enabled' => false) do
      info = NewRelic::Agent::MethodTracerHelpers.code_information(The::Example, :class_method)

      assert_equal NewRelic::EMPTY_HASH, info
    end
  end

  def test_uses_cache_if_an_object_and_method_combo_have_already_been_seen
    with_config(:'code_level_metrics.enabled' => true) do
      object = The::Example.new
      method_name = :instance_method
      cached_info = 'Badger'
      cache = {"#{object.object_id}#{method_name}" => cached_info}
      NewRelic::Agent::MethodTracerHelpers.instance_variable_set(:@code_information, cache)
      info = NewRelic::Agent::MethodTracerHelpers.code_information(object, method_name)

      assert_equal cached_info, info
    end
  end

  def test_provides_accurate_info_for_a_class_method
    with_config(:'code_level_metrics.enabled' => true) do
      info = NewRelic::Agent::MethodTracerHelpers.code_information(The::Example.singleton_class, :class_method)

      assert_equal({filepath: __FILE__,
        lineno: The::Example.method(:class_method).source_location.last,
        function: 'self.class_method',
        namespace: 'The::Example'},
        info)
    end
  end

  def test_provides_accurate_info_for_an_instance_method
    with_config(:'code_level_metrics.enabled' => true) do
      info = NewRelic::Agent::MethodTracerHelpers.code_information(::The::Example, :instance_method)

      assert_equal({filepath: __FILE__,
        lineno: The::Example.instance_method(:instance_method).source_location.last,
        function: 'instance_method',
        namespace: 'The::Example'},
        info)
    end
  end

  def test_provides_accurate_info_for_a_private_instance_method
    with_config(:'code_level_metrics.enabled' => true) do
      info = NewRelic::Agent::MethodTracerHelpers.code_information(::The::Example, :private_method)

      assert_equal({filepath: __FILE__,
        lineno: The::Example.instance_method(:private_method).source_location.last,
        function: 'private_method',
        namespace: 'The::Example'},
        info)
    end
  end

  def test_provides_accurate_info_for_an_anonymous_instance_method
    with_config(:'code_level_metrics.enabled' => true) do
      klass = Class.new do
        def an_instance_method; end
      end
      info = NewRelic::Agent::MethodTracerHelpers.code_information(klass, :an_instance_method)

      assert_equal({filepath: __FILE__,
        lineno: klass.instance_method(:an_instance_method).source_location.last,
        function: 'an_instance_method',
        namespace: '(Anonymous)'},
        info)
    end
  end

  def test_provides_accurate_info_for_an_anonymous_class_method
    with_config(:'code_level_metrics.enabled' => true) do
      klass = Class.new do
        def self.a_class_method; end
      end
      info = NewRelic::Agent::MethodTracerHelpers.code_information(klass, :a_class_method)

      assert_equal({filepath: __FILE__,
        lineno: klass.method(:a_class_method).source_location.last,
        function: 'self.a_class_method',
        namespace: '(Anonymous)'},
        info)
    end
  end

  def test_clm_memoization_hash_uses_frozen_keys_and_values
    helped = Class.new do
      include NewRelic::Agent::MethodTracerHelpers
    end.new
    with_config(:'code_level_metrics.enabled' => true) do
      helped.code_information(::The::Example, :instance_method)
      memoized = helped.instance_variable_get(:@code_information)

      assert memoized
      assert_equal(1, memoized.keys.size)
      assert_predicate memoized.keys.first, :frozen?
      assert_predicate memoized.values.first, :frozen?
    end
  end

  if defined?(::Rails::VERSION::MAJOR) && ::Rails::VERSION::MAJOR >= 7
    def test_provides_info_for_no_method_on_controller
      skip_unless_minitest5_or_above

      with_config(:'code_level_metrics.enabled' => true) do
        info = NewRelic::Agent::MethodTracerHelpers.code_information(TestController, :a_method)

        assert_equal({filepath: Rails.root.join('app/controllers/test_controller.rb').to_s,
          lineno: 1,
          function: 'a_method',
          namespace: 'TestController'},
          info)
      end
    end
  end

  if defined?(::Rails::VERSION::MAJOR) && ::Rails::VERSION::MAJOR >= 7
    def test_controller_info_no_filepath
      skip_unless_minitest5_or_above

      with_config(:'code_level_metrics.enabled' => true) do
        info = NewRelic::Agent::MethodTracerHelpers.send(:controller_info, Object, :a_method, false)

        assert_equal NewRelic::EMPTY_ARRAY, info
      end
    end
  end

  if defined?(::Rails::VERSION::MAJOR) && ::Rails::VERSION::MAJOR >= 7
    def test_code_information_returns_empty_hash_when_no_info_is_available
      with_config(:'code_level_metrics.enabled' => true) do
        object = String
        method_name = :a_method
        NewRelic::Agent::MethodTracerHelpers.stub(:namespace_and_location, [], [object, method_name]) do
          info = NewRelic::Agent::MethodTracerHelpers.code_information(object, method_name)

          assert_equal NewRelic::EMPTY_HASH, info
        end
      end
    end
  end
end
