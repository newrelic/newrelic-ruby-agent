# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../test_helper'

class NewRelic::LanguageSupportTest < Minitest::Test
  def test_object_space_usable_on_jruby_with_object_space_enabled
    return unless NewRelic::LanguageSupport.jruby?

    require 'jruby'
    JRuby.objectspace = true

    assert_truthy NewRelic::LanguageSupport.object_space_usable?
  end

  def test_object_space_not_usable_on_jruby_with_object_space_disabled
    return unless NewRelic::LanguageSupport.jruby?

    require 'jruby'
    JRuby.objectspace = false

    assert_falsy NewRelic::LanguageSupport.object_space_usable?
  end

  def test_gc_profiler_unavailable_without_constant
    undefine_constant(:'GC::Profiler') do
      refute NewRelic::LanguageSupport.gc_profiler_usable?
    end
  end

  def test_gc_profiler_unavailable_on_jruby
    return unless NewRelic::LanguageSupport.jruby?

    refute NewRelic::LanguageSupport.gc_profiler_usable?
  end

  def test_gc_profiler_disabled_without_constant
    undefine_constant(:'GC::Profiler') do
      refute NewRelic::LanguageSupport.gc_profiler_enabled?
    end
  end

  if NewRelic::LanguageSupport.gc_profiler_usable?
    def test_gc_profiler_disabled_when_enabled_is_falsy
      ::GC::Profiler.stubs(:enabled?).returns(false)

      refute NewRelic::LanguageSupport.gc_profiler_enabled?
    end

    def test_gc_profiler_enabled
      ::GC::Profiler.stubs(:enabled?).returns(true)

      assert_predicate NewRelic::LanguageSupport, :gc_profiler_enabled?
    end

    def test_gc_profiler_enabled_when_response_is_only_truthy
      ::GC::Profiler.stubs(:enabled?).returns(0)

      assert_predicate NewRelic::LanguageSupport, :gc_profiler_enabled?
    end

    def test_gc_profiler_enabled_when_config_is_disabled
      ::GC::Profiler.stubs(:enabled?).returns(true)

      with_config(:disable_gc_profiler => true) do
        refute NewRelic::LanguageSupport.gc_profiler_enabled?
      end
    end
  end

  def test_gc_profiler_disabled_on_jruby
    return unless defined?(::GC::Profiler) && NewRelic::LanguageSupport.jruby?

    ::GC::Profiler.stubs(:enabled?).returns(true)

    refute NewRelic::LanguageSupport.gc_profiler_enabled?
  end

  module ::Outer
    class Included
    end
  end

  class ::Excluded
  end

  module ::ContainsAnObject
    class ContainedObject
    end
  end

  def test_should_look_within_module
    assert_equal ::Outer::Included, NewRelic::LanguageSupport.constantize("Outer::Included")
  end

  def test_shouldnt_look_outside_module_for_class
    assert_nil NewRelic::LanguageSupport.constantize("Outer::Excluded")
  end

  def test_shouldnt_look_outside_module_for_module
    assert_nil NewRelic::LanguageSupport.constantize("Outer::Outer")
  end

  def test_should_allow_object_in_module_names
    assert_equal ::ContainsAnObject::ContainedObject,
      NewRelic::LanguageSupport.constantize("ContainsAnObject::ContainedObject")
  end

  def test_should_camelize_names_with_hyphens
    name = 'concurrent-ruby'

    assert_equal 'ConcurrentRuby', NewRelic::LanguageSupport.camelize(name)
  end

  def test_should_camelize_names_with_underscores
    name = 'delayed_job'

    assert_equal 'DelayedJob', NewRelic::LanguageSupport.camelize(name)
  end

  def test_should_camelize_names_with_underscores_and_hyphens
    name = 'newrelic-infinite_tracing'

    assert_equal 'NewrelicInfiniteTracing', NewRelic::LanguageSupport.camelize(name)
  end
end
