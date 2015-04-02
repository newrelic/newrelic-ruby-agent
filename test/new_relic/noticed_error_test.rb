# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','test_helper'))
require 'new_relic/agent/transaction/attributes'

class NewRelic::Agent::NoticedErrorTest < Minitest::Test
  include NewRelic::TestHelpers::Exceptions

  def setup
    @path = 'foo/bar/baz'

    freeze_time
    @time = Time.now

    @custom_attributes = NewRelic::Agent::Transaction::Attributes.new(NewRelic::Agent.instance.attribute_filter)
    @agent_attributes  = NewRelic::Agent::Transaction::Attributes.new(NewRelic::Agent.instance.attribute_filter)
    @intrinsic_attributes = NewRelic::Agent::Transaction::Attributes.new(NewRelic::Agent.instance.attribute_filter)

    @params = {
      'key' => 'val',
      :custom_params => { :user => 'params' },

      :custom_attributes    => @custom_attributes,
      :agent_attributes     => @agent_attributes,
      :intrinsic_attributes => @intrinsic_attributes
    }
  end

  def test_to_collector_array
    e = TestError.new('test exception')
    error = NewRelic::NoticedError.new(@path, @params, e, @time)
    expected = [
      (@time.to_f * 1000).round,
      @path,
      'test exception',
      'NewRelic::TestHelpers::Exceptions::TestError',
      {
        'key' => 'val',
        'userAttributes'  => { 'user' => 'params' },
        'agentAttributes' => {},
        'intrinsics'      => {}
      }
    ]
    assert_equal expected, error.to_collector_array
  end

  def test_to_collector_array_merges_custom_attributes_and_params
    e = TestError.new('test exception')
    @custom_attributes.add(:custom, "attribute")
    error = NewRelic::NoticedError.new(@path, @params, e, @time)

    actual = extract_attributes(error)
    expected = {
      'key'    => 'val',
      'userAttributes' => {
        'user'   => 'params',
        'custom' => 'attribute'
      },
      'agentAttributes' => {},
      'intrinsics'      => {}
    }

    assert_equal expected, actual
  end

  def test_to_collector_array_includes_agent_attributes
    e = TestError.new('test exception')
    @agent_attributes.add(:agent, "attribute")
    error = NewRelic::NoticedError.new(@path, @params, e, @time)

    actual = extract_attributes(error)
    assert_equal({"agent" => "attribute"}, actual["agentAttributes"])
  end

  def test_to_collector_array_includes_intrinsic_attributes
    e = TestError.new('test exception')
    @intrinsic_attributes.add(:intrinsic, "attribute")
    error = NewRelic::NoticedError.new(@path, @params, e, @time)

    actual = extract_attributes(error)
    assert_equal({"intrinsic" => "attribute"}, actual["intrinsics"])
  end

  def test_to_collector_array_happy_without_attribute_collections
    params = {}
    error = NewRelic::NoticedError.new(@path, params, "BOOM")

    expected = [
      (@time.to_f * 1000).round,
      @path,
      "BOOM",
      "Error",
      {
        'userAttributes'  => {},
        'agentAttributes' => {},
        'intrinsics'      => {}
      }
    ]
    assert_equal expected, error.to_collector_array
  end

  def test_to_collector_array_with_bad_values
    error = NewRelic::NoticedError.new(@path, @params, nil, Rational(10, 1))
    expected = [
      10_000.0,
      @path,
      "<no message>",
      "Error",
      {
        'key' => 'val',
        'userAttributes'  => { 'user' => 'params' },
        'agentAttributes' => {},
        'intrinsics'      => {}
      }
    ]
    assert_equal expected, error.to_collector_array
  end

  def test_handles_non_string_exception_messages
    e = Exception.new({ :non => :string })
    error = NewRelic::NoticedError.new(@path, @params, e, @time)
    assert_equal(String, error.message.class)
  end

  def test_strips_message_from_exceptions_in_high_security_mode
    with_config(:high_security => true) do
      e = TestError.new('test exception')
      error = NewRelic::NoticedError.new(@path, @params, e, @time)

      assert_equal NewRelic::NoticedError::STRIPPED_EXCEPTION_REPLACEMENT_MESSAGE, error.message
    end
  end

  def test_permits_messages_from_whitelisted_exceptions_in_high_security_mode
    with_config(:'strip_exception_messages.whitelist' => 'NewRelic::TestHelpers::Exceptions::TestError') do
      e = TestError.new('whitelisted test exception')
      error = NewRelic::NoticedError.new(@path, @params, e, @time)

      assert_equal 'whitelisted test exception', error.message
    end
  end

  def test_whitelisted_returns_nil_with_an_empty_whitelist
    with_config(:'strip_exception_messages.whitelist' => '') do
      assert_falsy NewRelic::NoticedError.passes_message_whitelist(TestError)
    end
  end

  def test_whitelisted_returns_nil_when_error_is_not_in_whitelist
    with_config(:'strip_exception_messages.whitelist' => 'YourErrorIsInAnotherCastle') do
      assert_falsy NewRelic::NoticedError.passes_message_whitelist(TestError)
    end
  end

  def test_whitelisted_is_true_when_error_is_in_whitelist
    with_config(:'strip_exception_messages.whitelist' => 'OtherException,NewRelic::TestHelpers::Exceptions::TestError') do
      assert_truthy NewRelic::NoticedError.passes_message_whitelist(TestError)
    end
  end

  def test_whitelisted_ignores_nonexistent_exception_types_in_whitelist
    with_config(:'strip_exception_messages.whitelist' => 'NonExistent::Exception,NewRelic::TestHelpers::Exceptions::TestError') do
      assert_truthy NewRelic::NoticedError.passes_message_whitelist(TestError)
    end
  end

  def test_whitelisted_is_true_when_an_exceptions_ancestor_is_whitelisted
    with_config(:'strip_exception_messages.whitelist' => 'NewRelic::TestHelpers::Exceptions::ParentException') do
      assert_truthy NewRelic::NoticedError.passes_message_whitelist(ChildException)
    end
  end

  def test_handles_exception_with_nil_original_exception
    e = Exception.new('Buffy FOREVER')
    e.stubs(:original_exception).returns(nil)
    error = NewRelic::NoticedError.new(@path, @params, e, @time)
    assert_equal(error.message.to_s, 'Buffy FOREVER')
  end

  def test_pulls_out_attributes_from_incoming_data
    params = {
      :custom_attributes    => @custom_attributes,
      :agent_attributes     => @agent_attributes,
      :intrinsic_attributes => @intrinsic_attributes,
    }

    error = NewRelic::NoticedError.new(@path, params, Exception.new("O_o"))

    assert_empty error.params

    assert_equal @custom_attributes, error.custom_attributes
    assert_equal @agent_attributes, error.agent_attributes
    assert_equal @intrinsic_attributes, error.intrinsic_attributes
  end

  def test_intrinsics_always_get_sent
    with_config(:'error_collector.attributes.enabled' => false) do
      intrinsic_attributes = NewRelic::Agent::Transaction::IntrinsicAttributes.new(NewRelic::Agent.instance.attribute_filter)
      intrinsic_attributes.add(:intrinsic, "attribute")

      params = { :intrinsic_attributes => intrinsic_attributes }
      error = NewRelic::NoticedError.new(@path, params, Exception.new("O_o"))

      serialized_attributes = extract_attributes(error)
      assert_equal({ "intrinsic" => "attribute" }, serialized_attributes["intrinsics"])
    end
  end

  def extract_attributes(error)
    error.to_collector_array[4]
  end
end
