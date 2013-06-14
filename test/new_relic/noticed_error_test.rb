# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','test_helper'))

class NoticedErrorTestException < StandardError; end
class ParentException < Exception; end
class ChildException < ParentException; end

class NewRelic::Agent::NoticedErrorTest < Test::Unit::TestCase
  def setup
    @path = 'foo/bar/baz'
    @params = { 'key' => 'val' }
    @time = Time.now
  end

  def test_to_collector_array
    e = NoticedErrorTestException.new('test exception')
    error = NewRelic::NoticedError.new(@path, @params, e, @time)
    expected = [
      (@time.to_f * 1000).round, @path, 'test exception', 'NoticedErrorTestException', @params
    ]
    assert_equal expected, error.to_collector_array
  end

  def test_to_collector_array_with_bad_values
    error = NewRelic::NoticedError.new(@path, @params, nil, Rational(10, 1))
    expected = [
      10_000.0, @path, "<no message>", "Error", @params
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
      e = NoticedErrorTestException.new('test exception')
      error = NewRelic::NoticedError.new(@path, @params, e, @time)

      assert_equal NewRelic::NoticedError::STRIPPED_EXCEPTION_REPLACEMENT_MESSAGE, error.message
    end
  end

  def test_permits_messages_from_whitelisted_exceptions_in_high_security_mode
    with_config(:'strip_exception_messages.whitelist' => 'NoticedErrorTestException') do
      e = NoticedErrorTestException.new('whitelisted test exception')
      error = NewRelic::NoticedError.new(@path, @params, e, @time)

      assert_equal 'whitelisted test exception', error.message
    end
  end

  def test_whitelisted_returns_nil_with_an_empty_whitelist
    with_config(:'strip_exception_messages.whitelist' => '') do
      e = NoticedErrorTestException.new('whitelisted test exception')
      error = NewRelic::NoticedError.new(@path, @params, e, @time)

      assert_falsy error.whitelisted?
    end
  end

  def test_whitelisted_returns_nil_when_error_is_not_in_whitelist
    with_config(:'strip_exception_messages.whitelist' => 'YourErrorIsInAnotherCastle') do
      e = NoticedErrorTestException.new('whitelisted test exception')
      error = NewRelic::NoticedError.new(@path, @params, e, @time)

      assert_falsy error.whitelisted?
    end
  end

  def test_whitelisted_is_true_when_error_is_in_whitelist
    with_config(:'strip_exception_messages.whitelist' => 'OtherException,NoticedErrorTestException') do
      test_exception_class = NoticedErrorTestException
      e = test_exception_class.new('whitelisted test exception')
      error = NewRelic::NoticedError.new(@path, @params, e, @time)

      assert_truthy error.whitelisted?
    end
  end

  def test_whitelisted_ignores_nonexistent_exception_types_in_whitelist
    with_config(:'strip_exception_messages.whitelist' => 'NonExistent::Exception,NoticedErrorTestException') do
      test_exception_class = NoticedErrorTestException
      e = test_exception_class.new('whitelisted test exception')
      error = NewRelic::NoticedError.new(@path, @params, e, @time)

      assert_truthy error.whitelisted?
    end
  end

  def test_whitelisted_is_true_when_an_exceptions_ancestor_is_whitelisted
    with_config(:'strip_exception_messages.whitelist' => 'ParentException') do
      e = ChildException.new('whitelisted test exception')
      error = NewRelic::NoticedError.new(@path, @params, e, @time)

      assert_truthy error.whitelisted?
    end
  end
end
