# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..','..','test_helper'))
require 'new_relic/agent/transaction/attributes'

class AttributesTest < Minitest::Test
  def setup
    @attributes = NewRelic::Agent::Transaction::Attributes.new
  end

  def test_adding_custom_attributes
    @attributes.add_custom(:foo, "bar")
    assert_equal "bar", @attributes.custom[:foo]
  end

  def test_adding_agent_attributes
    @attributes.add_agent(:foo, "bar")
    assert_equal "bar", @attributes.agent[:foo]
  end

  def test_adding_intrinsic_attributes
    @attributes.add_intrinsic(:foo, "bar")
    assert_equal "bar", @attributes.intrinsic[:foo]
  end
end