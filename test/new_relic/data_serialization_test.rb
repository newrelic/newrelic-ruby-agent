require File.expand_path(File.join(File.dirname(__FILE__),'..', 'test_helper'))
require 'new_relic/data_serialization'
class NewRelic::DataSerializationTest < Test::Unit::TestCase
  def test_read_and_write_from_file_read_only
    file = './log/newrelic_agent_store.db'
    File.open(file, 'w') do |f|
      f.write(Marshal.dump('a happy string'))
    end
    NewRelic::DataSerialization.read_and_write_to_file do |data|
      assert_equal('a happy string', data, "should pull the dumped item from the file")
      nil # must explicitly return nil or the return value will be dumped
    end
    assert_equal(0, File.size(file), "Should not leave any data in the file")
  end

  def test_read_and_write_to_file_dumping_contents
    file = './log/newrelic_agent_store.db'
    expected_contents = Marshal.dump('a happy string')
    NewRelic::DataSerialization.read_and_write_to_file do
      'a happy string'
    end
    assert_equal(expected_contents, File.read(file), "should have dumped the contents")
  end

  def test_read_and_write_to_file_yields_old_data
    file = './log/newrelic_agent_store.db'
    expected_contents = 'a happy string'
    File.open(file, 'w') do |f|
      f.write(Marshal.dump(expected_contents))
    end
    contents = nil
    NewRelic::DataSerialization.read_and_write_to_file do |old_data|
      contents = old_data
      'a happy string'
    end
    assert_equal(contents, expected_contents, "should have dumped the contents")
  end

  def test_read_and_write_to_file_round_trip
    old_data = nil
    NewRelic::DataSerialization.read_and_write_to_file do |data|
      old_data = data
      'a' * 30
    end
    NewRelic::DataSerialization.read_and_write_to_file do |data|
      assert_equal('a'*30, data, "should be the same after serialization")
    end
  end

  def test_should_send_data
    NewRelic::DataSerialization.expects(:max_size).returns(20)
    NewRelic::DataSerialization.read_and_write_to_file do
      "a" * 30
    end
    assert(NewRelic::DataSerialization.should_send_data?, 'Should be over limit')
  end

  def test_should_send_data_disabled
    NewRelic::Control.instance.expects(:disable_serialization?).returns(true)
    assert(NewRelic::DataSerialization.should_send_data?, 'should send data when disabled')
  end

  def test_should_send_data_under_limit
    NewRelic::DataSerialization.expects(:max_size).returns(20)
    NewRelic::DataSerialization.read_and_write_to_file do
      "a" * 10
    end
    assert(!NewRelic::DataSerialization.should_send_data?, 'Should be under the limit')
  end
end
