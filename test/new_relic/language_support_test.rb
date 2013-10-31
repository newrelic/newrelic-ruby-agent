# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','test_helper'))

class NewRelic::LanguageSupportTest < Test::Unit::TestCase
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
end
