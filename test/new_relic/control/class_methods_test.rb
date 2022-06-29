# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require 'new_relic/control/class_methods'

class BaseClassMethods
  # stub class to enable testing of the module
  include NewRelic::Control::ClassMethods

  def initialize
    @instance = nil
  end
end

class NewRelic::Control::ClassMethodsTest < Minitest::Test
  def setup
    @base = ::BaseClassMethods.new
    super
  end

  def test_instance
    assert_nil(@base.instance_variable_get(:@instance), 'instance should start out nil')
    @base.expects(:new_instance).returns('a new instance')
    assert_equal('a new instance', @base.instance, "should return the result from the #new_instance call")
  end

  def test_load_test_framework
    local_env = mock('local env')
    # a loose requirement here because the tests will *all* break if
    # this does not work.
    NewRelic::Control::Frameworks::Test.expects(:new).with(local_env, instance_of(String))
    @base.expects(:local_env).returns(local_env)
    @base.load_test_framework
  end

  def test_load_framework_class_existing
    %w[rails rails3 sinatra ruby external].each do |type|
      @base.load_framework_class(type)
    end
  end

  def test_load_framework_class_missing
    # this is used to allow other people to insert frameworks without
    # having the file in our agent, i.e. define your own
    # NewRelic::Control::Framework::FooBar
    assert_raises(NameError) do
      @base.load_framework_class('missing')
    end
  end

  def test_camelize
    assert_equal 'TestConstantize', @base.camelize('test_constantize')
  end
end
