require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))
require 'new_relic/transaction_sample/segment'
class NewRelic::TransactionSample::SegmentTest < Test::Unit::TestCase
  def test_segment_creation
    # basic smoke test
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)
    assert_equal NewRelic::TransactionSample::Segment, s.class
  end

  def test_readers
    t = Time.now
    s = NewRelic::TransactionSample::Segment.new(t, 'Custom/test/metric', nil)
    assert_equal(t, s.entry_timestamp)
    assert_equal(nil, s.exit_timestamp)
    assert_equal(nil, s.parent_segment)
    assert_equal('Custom/test/metric', s.metric_name)
    assert_equal(s.object_id, s.segment_id)
  end

  def test_end_trace
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)
    t = Time.now
    s.end_trace(t)
    assert_equal(t, s.exit_timestamp)
  end
  
  def test_add_called_segment
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)
    assert_equal [], s.called_segments
    fake_segment = mock('segment')
    fake_segment.expects(:parent_segment=).with(s)
    s.add_called_segment(fake_segment)
    assert_equal([fake_segment], s.called_segments)
  end

  def test_to_s
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)    
    s.expects(:to_debug_str).with(0)
    s.to_s
  end

  def test_to_json
    t = Time.now
    s = NewRelic::TransactionSample::Segment.new(t, 'Custom/test/metric', nil)    
    assert_equal({ :entry_timestamp => t, :exit_timestamp => nil, :metric_name => 'Custom/test/metric', :segment_id => s.object_id }.to_json, s.to_json)
  end

  def test_path_string
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)
    assert_equal("Custom/test/metric[]", s.path_string)
    
    fake_segment = mock('segment')
    fake_segment.expects(:parent_segment=).with(s)
    fake_segment.expects(:path_string).returns('Custom/other/metric[]')
    

    s.add_called_segment(fake_segment)
    assert_equal("Custom/test/metric[Custom/other/metric[]]", s.path_string)
  end

  def test_to_s_compact
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)
    assert_equal("Custom/test/metric", s.to_s_compact)

    fake_segment = mock('segment')
    fake_segment.expects(:parent_segment=).with(s)
    fake_segment.expects(:to_s_compact).returns('Custom/other/metric')
    s.add_called_segment(fake_segment)

    assert_equal("Custom/test/metric{Custom/other/metric}", s.to_s_compact)
  end

  def test_to_debug_str
    raise 'needs more tests'
  end

  def test_called_segments_default
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)    
    assert_equal([], s.called_segments)
  end

  def test_called_segments_with_segments
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)
    fake_segment = mock('segment')
    fake_segment.expects(:parent_segment=).with(s)
    s.add_called_segment(fake_segment)

    assert_equal([fake_segment], s.called_segments)
  end
  
  def test_duration
    fake_entry_timestamp = mock('entry timestamp')
    fake_exit_timestamp = mock('exit timestamp')
    fake_result = mock('numeric')
    fake_exit_timestamp.expects(:-).with(fake_entry_timestamp).returns(fake_result)
    fake_result.expects(:to_f).returns(0.5)
    
    s = NewRelic::TransactionSample::Segment.new(fake_entry_timestamp, 'Custom/test/metric', nil)
    s.end_trace(fake_exit_timestamp)
    assert_equal(0.5, s.duration)
  end

  def test_exclusive_duration_no_children
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)
    s.expects(:duration).returns(0.5)
    assert_equal(0.5, s.exclusive_duration)
  end

  def test_exclusive_duration_with_children
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)

    s.expects(:duration).returns(0.5)
    
    fake_segment = mock('segment')
    fake_segment.expects(:parent_segment=).with(s)
    fake_segment.expects(:duration).returns(0.1)
    
    s.add_called_segment(fake_segment)

    assert_equal(0.4, s.exclusive_duration)
  end

  def test_count_segments_default
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)
    assert_equal(1, s.count_segments)
  end

  def test_count_segments_with_children
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)

    fake_segment = mock('segment')
    fake_segment.expects(:parent_segment=).with(s)
    fake_segment.expects(:count_segments).returns(1)

    s.add_called_segment(fake_segment)

    assert_equal(2, s.count_segments)
  end

  def test_truncate_default
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)

    assert_equal(1, s.truncate(1))
  end

  def test_truncate_with_children
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)
    
    fake_segment = mock('segment')
    fake_segment.expects(:parent_segment=).with(s)
    fake_segment.expects(:truncate).with(1).returns(1)

    fail "you try to test it, I mean, really."
  end

  def test_key_equals
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)
    # doing this to hold the reference to the hash
    params = {}
    s.params = params
    assert_equal(params, s.params)
    
    # should delegate to the same hash we have above
    s[:foo] = 'correct'

    assert_equal('correct', params[:foo])
  end

  def test_key
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)
    s.params = {:foo => 'correct'}
    assert_equal('correct', s[:foo])
  end
  
  def test_params
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)

    # should have a default value
    assert_equal(nil, s.instance_eval { @params })    
    assert_equal({}, s.params)

    # should otherwise take the value from the @params var
    s.instance_eval { @params = {:foo => 'correct'} }
    assert_equal({:foo => 'correct'}, s.params)
  end

  def test_each_segment_default
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)
    # in the base case it just yields the block to itself
    count = 0
    s.each_segment do |x|
      count += 1
      assert_equal(s, x)
    end
    # should only run once
    assert_equal(1, count)
  end

  def test_each_segment_with_children
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)

    fake_segment = mock('segment')
    fake_segment.expects(:parent_segment=).with(s)
    fake_segment.expects(:each_segment).yields(fake_segment)
    
    s.add_called_segment(fake_segment)

    count = 0
    s.each_segment do |x|
      count += 1
    end

    assert_equal(2, count)
  end

  def test_find_segment_default
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)
    id_to_find = s.segment_id
    # should return itself in the base case
    assert_equal(s, s.find_segment(id_to_find))
  end

  def test_find_segment_not_found
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)    
    assert_equal(nil, s.find_segment(-1))
  end

  def test_find_segment_with_children
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)
    id_to_find = s.segment_id
    # should return itself in the base case
    assert_equal(s, s.find_segment(id_to_find))    
  end
  
  def test_explain_sql
    # TODO holy mother of god
    raise 'needs more tests'
  end
  
  def test_params_equal
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)
    assert_equal(nil, s.instance_eval { @params })
    
    params = {:foo => 'correct'}
    
    s.params = params
    assert_equal(params, s.instance_eval { @params })
  end

  def test_handle_exception_in_explain
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)
    fake_error = mock('error')
    fake_error.expects(:message).returns('a message')
    fake_error.expects(:backtrace).returns(['a backtrace'])
    NewRelic::Control.instance.log.expects(:error).with('Error getting explain plan: a message')
    NewRelic::Control.instance.log.expects(:debug).with('a backtrace')
    s.handle_exception_in_explain(fake_error)
  end

  def test_obfuscated_sql
    sql = 'some sql'
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)
    s[:sql] = sql
    NewRelic::TransactionSample.expects(:obfuscate_sql).with(sql)
    s.obfuscated_sql
  end

  def test_called_segments_equals
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)
    assert_equal(nil, s.instance_eval { @called_segments })
    s.called_segments = [1, 2, 3]
    assert_equal([1, 2, 3], s.instance_eval { @called_segments })
  end

  def test_parent_segment_equals
    s = NewRelic::TransactionSample::Segment.new(Time.now, 'Custom/test/metric', nil)
    assert_equal(nil, s.instance_eval { @parent_segment })
    fake_segment = mock('segment')
    s.send(:parent_segment=, fake_segment)
    assert_equal(fake_segment, s.parent_segment)
  end
end

