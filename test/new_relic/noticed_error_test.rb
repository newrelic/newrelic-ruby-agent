# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','test_helper'))

class NewRelic::Agent::NoticedErrorTest < Minitest::Test
  include NewRelic::TestHelpers::Exceptions

  def setup
    @path = 'foo/bar/baz'
    @params = { 'key' => 'val' }
    @time = Time.now
  end

  def test_to_collector_array
    e = TestError.new('test exception')
    error = NewRelic::NoticedError.new(@path, @params, e, @time)
    expected = [
      (@time.to_f * 1000).round, @path, 'test exception', 'NewRelic::TestHelpers::Exceptions::TestError', @params
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

end
