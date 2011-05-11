require File.expand_path(File.join(File.dirname(__FILE__),'..', 'test_helper'))
require 'new_relic/data_serialization'
class NewRelic::DataSerializationTest < Test::Unit::TestCase
  def test_load_from_file
    file = './log/newrelic_agent_store.db'
    File.open(file, 'w') do |f|
      f.write(Marshal.dump('a happy string'))
    end
    assert_equal('a happy string', NewRelic::DataSerialization.load_from_file, "should pull the dumped item from the file")
    assert_equal(0, File.size(file), "Should not leave any data in the file")
  end

  def test_dump_to_file
    file = './log/newrelic_agent_store.db'
    expected_contents = Marshal.dump('a happy string')
    NewRelic::DataSerialization.dump_to_file do
      'a happy string'
    end
    assert_equal(expected_contents, File.read(file), "should have dumped the contents")
  end

  def test_round_trip
    NewRelic::DataSerialization.dump_to_file do
      'a' * 30
    end
    assert_equal('a'*30, NewRelic::DataSerialization.load_from_file, "should be the same after serialization")
  end

  def test_should_send_data
    NewRelic::DataSerialization.expects(:max_size).returns(20)
    NewRelic::DataSerialization.dump_to_file do
      "a" * 30
    end
    assert(NewRelic::DataSerialization.should_send_data?, 'Should be over limit')
  end
end
