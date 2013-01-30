require File.expand_path(File.join(File.dirname(__FILE__),'..','test_helper'))

class NewRelic::Agent::NoticedErrorTest < Test::Unit::TestCase
  def setup
    @path = 'foo/bar/baz'
    @params = { 'key' => 'val' }
    @time = Time.now
  end

  def test_to_collector_array
    e = Exception.new('test exception')
    error = NewRelic::NoticedError.new(@path, @params, e, @time)
    expected = [
      (@time.to_f * 1000).round, @path, 'test exception', 'Exception', @params
    ]
    assert_equal expected, error.to_collector_array
  end

  def test_handles_non_string_exception_messages
    e = Exception.new({ :non => :string })
    error = NewRelic::NoticedError.new(@path, @params, e, @time)
    assert_equal(String, error.message.class)
  end
end
