# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','test_helper'))

class NewRelic::LanguageSupportTest < Test::Unit::TestCase
  def test_object_space_enabled_true_without_jruby_with_object_space
    undefine_constant(:JRuby) do
      define_constant(:ObjectSpace, mock()) do
        assert_truthy NewRelic::LanguageSupport.object_space_enabled?
      end
    end
  end

  def test_object_space_enabled_false_without_object_space_without_jruby
    undefine_constant(:ObjectSpace) do
      undefine_constant(:JRuby) do
        assert_falsy NewRelic::LanguageSupport.object_space_enabled?
      end
    end
  end

  def test_object_space_enabled_true_if_enabled_in_jruby_without_object_space
    fake_runtime = mock(:is_object_space_enabled => true)
    fake_jruby = mock(:runtime => fake_runtime)

    define_constant(:JRuby, fake_jruby) do
      undefine_constant(:ObjectSpace) do
        assert_truthy NewRelic::LanguageSupport.object_space_enabled?
      end
    end
  end

  def test_object_space_enabled_false_if_disabled_in_jruby_without_object_space
    fake_runtime = mock(:is_object_space_enabled => false)
    fake_jruby = mock(:runtime => fake_runtime)

    define_constant(:JRuby, fake_jruby) do
      undefine_constant(:ObjectSpace) do
        assert_falsy NewRelic::LanguageSupport.object_space_enabled?
      end
    end
  end
end
