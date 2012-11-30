require File.expand_path(File.join(File.dirname(__FILE__),'..','test_helper'))

class NewRelic::Agent::NoticedErrorTest < Test::Unit::TestCase
  def test_to_collector_array
    time = Time.now
    error = NewRelic::NoticedError.new('path', {'key' => 'val'},
                                       Exception.new('test exception'), time)
    expected = [
      (time.to_f * 1000).round, 'path', 'test exception', 'Exception',
      {'key' => 'val'}
    ]
    assert_equal expected, error.to_collector_array
  end
end
