require File.expand_path(File.join(File.dirname(__FILE__),'..', 'test_helper')) 
require 'new_relic/data_serialization'
class NewRelic::DataSerializationTest < Test::Unit::TestCase
  def setup
    @ds = NewRelic::DataSerialization.new
    @ds.truncate_file
  end

  def test_truncate_file
    @ds.dump_to_file('foo')
    @ds.truncate_file
    assert_equal [], @ds.load_from_file
  end
  
  def test_dump
    result = @ds.dump({'whee' => 'whee'})
    assert_equal "\004\b{\006\"\twhee\"\twhee", result
  end

  def test_load
    result = @ds.load("\004\b{\006\"\twhee\"\twhee")
    assert_equal({'whee' => 'whee'}, result)
  end

  def test_round_trip
    assert_equal({'whee' => 'whee'}, @ds.load(@ds.dump({'whee' => 'whee'})))
  end

  def test_dump_to_file
    fake_file = mock('a file')
    fake_file.expects(:puts).with('{"whee":"whee"}')
    File.expects(:open).with('./log/newrelic_agent_store.db', 'a').yields(fake_file)
    @ds.expects(:dump).returns('{"whee":"whee"}')
    @ds.dump_to_file({'whee' => 'whee'})
  end

  def test_load_from_file
    fake_file = mock('a file')
    fake_file.expects(:readlines).returns(['a line'])
    File.expects(:open).with('./log/newrelic_agent_store.db', 'r').yields(fake_file)
    @ds.expects(:load).with('a line').returns({"whee" => "whee"})
    @ds.load_from_file
  end

  def test_file_round_trip
    @ds.dump_to_file({'whee' => 'whee'})
    assert_equal([{'whee' => 'whee'}], @ds.load_from_file)
  end

  def test_zzz_dumping_interesting_stuff
    @ds.dump_to_file(NewRelic::Agent.instance.stats_engine)
  end

  def test_multiple_dumps
    @ds.dump_to_file('foo')
    @ds.dump_to_file('bar')
    @ds.dump_to_file('baz')
    assert_equal ['foo', 'bar', 'baz'], @ds.load_from_file
  end

  def test_should_send_data
    File.open(@ds.file_path, 'w') do |f|
      f.truncate(0)
      f.write(" " * 9999)
    end
    assert !@ds.should_send_data
    File.open(@ds.file_path, 'w') do |f|
      f.truncate(0)
      f.write(" " * 10_000)
    end
    assert @ds.should_send_data
  end
end
