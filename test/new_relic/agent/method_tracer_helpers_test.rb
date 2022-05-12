# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))

module ::The
  class Example
    def self.class_method; end
    def instance_method; end
  end
end

class NewRelic::Agent::MethodTracerHelpersTest < Minitest::Test
  # TODO: trace_execution_scoped should have test coverage

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
      assert The::Example, klass
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
end
