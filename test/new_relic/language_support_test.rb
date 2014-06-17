# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','test_helper'))

class NewRelic::LanguageSupportTest < Minitest::Test
  include ::NewRelic::TestHelpers::RuntimeDetection

  def test_object_space_usable_on_jruby_with_object_space_enabled
    return unless jruby?
    JRuby.objectspace = true
    assert_truthy NewRelic::LanguageSupport.object_space_usable?
  end

  def test_object_space_not_usable_on_jruby_with_object_space_disabled
    return unless jruby?
    JRuby.objectspace = false
    assert_falsy NewRelic::LanguageSupport.object_space_usable?
  end

  def test_object_space_not_usable_on_rubinius
    return unless rubinius?
    assert_falsy NewRelic::LanguageSupport.object_space_usable?
  end

  def test_gc_profiler_unavailable_without_constant
    undefine_constant(:'GC::Profiler') do
      assert_equal false, NewRelic::LanguageSupport.gc_profiler_usable?
    end
  end

  def test_gc_profiler_unavailable_on_jruby
    return unless jruby?
    assert_equal false, NewRelic::LanguageSupport.gc_profiler_usable?
  end

  def test_gc_profiler_disabled_without_constant
    undefine_constant(:'GC::Profiler') do
      assert_equal false, NewRelic::LanguageSupport.gc_profiler_enabled?
    end
  end

  if NewRelic::LanguageSupport.gc_profiler_usable?
    def test_gc_profiler_disabled_when_enabled_is_falsy
      ::GC::Profiler.stubs(:enabled?).returns(false)
      assert_equal false, NewRelic::LanguageSupport.gc_profiler_enabled?
    end

    def test_gc_profiler_enabled
      ::GC::Profiler.stubs(:enabled?).returns(true)
      assert_equal true, NewRelic::LanguageSupport.gc_profiler_enabled?
    end

    def test_gc_profiler_enabled_when_response_is_only_truthy
      ::GC::Profiler.stubs(:enabled?).returns(0)
      assert_equal true, NewRelic::LanguageSupport.gc_profiler_enabled?
    end

    def test_gc_profiler_enabled_when_config_is_disabled
      ::GC::Profiler.stubs(:enabled?).returns(true)
      with_config(:disable_gc_profiler => true) do
        refute NewRelic::LanguageSupport.gc_profiler_enabled?
      end
    end
  end

  def test_gc_profiler_disabled_on_jruby
    return unless defined?(::GC::Profiler) && jruby?

    ::GC::Profiler.stubs(:enabled?).returns(true)
    assert_equal false, NewRelic::LanguageSupport.gc_profiler_enabled?
  end
end
