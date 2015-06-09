# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'test_helper'))
require 'new_relic/agent/transaction/trace_node'

class NewRelic::Agent::Transaction::TraceNodeTest < Minitest::Test
  def test_node_creation
    # basic smoke test
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')
    assert_equal NewRelic::Agent::Transaction::TraceNode, s.class
  end

  def test_readers
    t = Time.now
    s = NewRelic::Agent::Transaction::TraceNode.new(t, 'Custom/test/metric')
    assert_equal(t, s.entry_timestamp)
    assert_equal(nil, s.exit_timestamp)
    assert_equal(nil, s.parent_node)
    assert_equal('Custom/test/metric', s.metric_name)
  end

  def test_end_trace
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')
    t = Time.now
    s.end_trace(t)
    assert_equal(t, s.exit_timestamp)
  end

  def test_add_called_node
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')
    assert_equal [], s.called_nodes
    fake_node = mock('node')
    fake_node.expects(:parent_node=).with(s)
    s.add_called_node(fake_node)
    assert_equal([fake_node], s.called_nodes)
  end

  def test_to_s
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')
    s.expects(:to_debug_str).with(0)
    s.to_s
  end

  def test_to_array
    parent = NewRelic::Agent::Transaction::TraceNode.new(1, 'Custom/test/parent')
    parent.params[:test] = 'value'
    child = NewRelic::Agent::Transaction::TraceNode.new(2, 'Custom/test/child')
    child.end_trace(3)
    parent.add_called_node(child)
    parent.end_trace(4)
    expected_array = [1000, 4000, 'Custom/test/parent', {:test => 'value'},
                      [[2000, 3000, 'Custom/test/child', {}, []]]]
    assert_equal(expected_array, parent.to_array)
  end

  def test_to_array_with_bad_values
    node = NewRelic::Agent::Transaction::TraceNode.new(nil, nil)
    node.end_trace(Rational(10, 1))
    expected = [0, 10_000.0, "<unknown>", {}, []]
    assert_equal(expected, node.to_array)
  end

  def test_path_string
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')
    assert_equal("Custom/test/metric[]", s.path_string)

    fake_node = mock('node')
    fake_node.expects(:parent_node=).with(s)
    fake_node.expects(:path_string).returns('Custom/other/metric[]')


    s.add_called_node(fake_node)
    assert_equal("Custom/test/metric[Custom/other/metric[]]", s.path_string)
  end

  def test_to_s_compact
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')
    assert_equal("Custom/test/metric", s.to_s_compact)

    fake_node = mock('node')
    fake_node.expects(:parent_node=).with(s)
    fake_node.expects(:to_s_compact).returns('Custom/other/metric')
    s.add_called_node(fake_node)

    assert_equal("Custom/test/metric{Custom/other/metric}", s.to_s_compact)
  end

  def test_to_debug_str_basic
    s = NewRelic::Agent::Transaction::TraceNode.new(0.0, 'Custom/test/metric')
    assert_equal(">>   0 ms [TraceNode] Custom/test/metric \n<<  n/a Custom/test/metric\n", s.to_debug_str(0))
  end

  def test_to_debug_str_with_params
    s = NewRelic::Agent::Transaction::TraceNode.new(0.0, 'Custom/test/metric')
    s.params = {:whee => 'a param'}
    assert_equal(">>   0 ms [TraceNode] Custom/test/metric \n    -whee            : a param\n<<  n/a Custom/test/metric\n", s.to_debug_str(0))
  end

  def test_to_debug_str_closed
    s = NewRelic::Agent::Transaction::TraceNode.new(0.0, 'Custom/test/metric')
    s.end_trace(0.1)
    assert_equal(">>   0 ms [TraceNode] Custom/test/metric \n<< 100 ms Custom/test/metric\n", s.to_debug_str(0))
  end

  def test_to_debug_str_closed_with_nonnumeric
    s = NewRelic::Agent::Transaction::TraceNode.new(0.0, 'Custom/test/metric')
    s.end_trace("0.1")
    assert_equal(">>   0 ms [TraceNode] Custom/test/metric \n<< 0.1 Custom/test/metric\n", s.to_debug_str(0))
  end

  def test_to_debug_str_one_child
    s = NewRelic::Agent::Transaction::TraceNode.new(0.0, 'Custom/test/metric')
    s.add_called_node(NewRelic::Agent::Transaction::TraceNode.new(0.1, 'Custom/test/other'))
    assert_equal(">>   0 ms [TraceNode] Custom/test/metric \n  >> 100 ms [TraceNode] Custom/test/other \n  <<  n/a Custom/test/other\n<<  n/a Custom/test/metric\n", s.to_debug_str(0))
    # try closing it
    s.called_nodes.first.end_trace(0.15)
    s.end_trace(0.2)
    assert_equal(">>   0 ms [TraceNode] Custom/test/metric \n  >> 100 ms [TraceNode] Custom/test/other \n  << 150 ms Custom/test/other\n<< 200 ms Custom/test/metric\n", s.to_debug_str(0))
  end

  def test_to_debug_str_multichild
    s = NewRelic::Agent::Transaction::TraceNode.new(0.0, 'Custom/test/metric')
    s.add_called_node(NewRelic::Agent::Transaction::TraceNode.new(0.1, 'Custom/test/other'))
    s.add_called_node(NewRelic::Agent::Transaction::TraceNode.new(0.11, 'Custom/test/extra'))
    assert_equal(">>   0 ms [TraceNode] Custom/test/metric \n  >> 100 ms [TraceNode] Custom/test/other \n  <<  n/a Custom/test/other\n  >> 110 ms [TraceNode] Custom/test/extra \n  <<  n/a Custom/test/extra\n<<  n/a Custom/test/metric\n", s.to_debug_str(0))
    ending = 0.12
    s.called_nodes.each { |x| x.end_trace(ending += 0.01) }
    s.end_trace(0.2)
    assert_equal(">>   0 ms [TraceNode] Custom/test/metric \n  >> 100 ms [TraceNode] Custom/test/other \n  << 130 ms Custom/test/other\n  >> 110 ms [TraceNode] Custom/test/extra \n  << 140 ms Custom/test/extra\n<< 200 ms Custom/test/metric\n", s.to_debug_str(0))
  end

  def test_to_debug_str_nested
    inner = NewRelic::Agent::Transaction::TraceNode.new(0.2, 'Custom/test/inner')
    middle = NewRelic::Agent::Transaction::TraceNode.new(0.1, 'Custom/test/middle')
    s = NewRelic::Agent::Transaction::TraceNode.new(0.0, 'Custom/test/metric')
    middle.add_called_node(inner)
    s.add_called_node(middle)
    assert_equal(">>   0 ms [TraceNode] Custom/test/metric \n  >> 100 ms [TraceNode] Custom/test/middle \n    >> 200 ms [TraceNode] Custom/test/inner \n    <<  n/a Custom/test/inner\n  <<  n/a Custom/test/middle\n<<  n/a Custom/test/metric\n", s.to_debug_str(0))

    # close them
    inner.end_trace(0.21)
    middle.end_trace(0.22)
    s.end_trace(0.23)
    assert_equal(">>   0 ms [TraceNode] Custom/test/metric \n  >> 100 ms [TraceNode] Custom/test/middle \n    >> 200 ms [TraceNode] Custom/test/inner \n    << 210 ms Custom/test/inner\n  << 220 ms Custom/test/middle\n<< 230 ms Custom/test/metric\n", s.to_debug_str(0))
  end

  def test_called_nodes_default
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')
    assert_equal([], s.called_nodes)
  end

  def test_called_nodes_with_nodes
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')
    fake_node = mock('node')
    fake_node.expects(:parent_node=).with(s)
    s.add_called_node(fake_node)

    assert_equal([fake_node], s.called_nodes)
  end

  def test_duration
    fake_entry_timestamp = mock('entry timestamp')
    fake_exit_timestamp = mock('exit timestamp')
    fake_result = mock('numeric')
    fake_exit_timestamp.expects(:-).with(fake_entry_timestamp).returns(fake_result)
    fake_result.expects(:to_f).returns(0.5)

    s = NewRelic::Agent::Transaction::TraceNode.new(fake_entry_timestamp, 'Custom/test/metric')
    s.end_trace(fake_exit_timestamp)
    assert_equal(0.5, s.duration)
  end

  def test_exclusive_duration_no_children
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')
    s.expects(:duration).returns(0.5)
    assert_equal(0.5, s.exclusive_duration)
  end

  def test_exclusive_duration_with_children
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')

    s.expects(:duration).returns(0.5)

    fake_node = mock('node')
    fake_node.expects(:parent_node=).with(s)
    fake_node.expects(:duration).returns(0.1)

    s.add_called_node(fake_node)

    assert_equal(0.4, s.exclusive_duration)
  end

  def test_count_nodes_default
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')
    assert_equal(1, s.count_nodes)
  end

  def test_count_nodes_with_children
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')

    fake_node = mock('node')
    fake_node.expects(:parent_node=).with(s)
    fake_node.expects(:count_nodes).returns(1)

    s.add_called_node(fake_node)

    assert_equal(2, s.count_nodes)
  end

  def test_key_equals
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')
    # doing this to hold the reference to the hash
    params = {}
    s.params = params
    assert_equal(params, s.params)

    # should delegate to the same hash we have above
    s[:foo] = 'correct'

    assert_equal('correct', params[:foo])
  end

  def test_key
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')
    s.params = {:foo => 'correct'}
    assert_equal('correct', s[:foo])
  end

  def test_params
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')

    # should have a default value
    assert_equal(nil, s.instance_eval { @params })
    assert_equal({}, s.params)

    # should otherwise take the value from the @params var
    s.instance_eval { @params = {:foo => 'correct'} }
    assert_equal({:foo => 'correct'}, s.params)
  end

  def test_each_node_default
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')
    # in the base case it just yields the block to itself
    count = 0
    s.each_node do |x|
      count += 1
      assert_equal(s, x)
    end
    # should only run once
    assert_equal(1, count)
  end

  def test_each_node_with_children
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')

    fake_node = mock('node')
    fake_node.expects(:parent_node=).with(s)
    fake_node.expects(:each_node).yields(fake_node)

    s.add_called_node(fake_node)

    count = 0
    s.each_node do |x|
      count += 1
    end

    assert_equal(2, count)
  end

  def test_each_node_with_nest_tracking
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')

    summary = mock('summary')
    summary.expects(:current_nest_count).twice.returns(0).then.returns(1)
    summary.expects(:current_nest_count=).twice
    s.each_node_with_nest_tracking do |x|
      summary
    end
  end

  def test_find_node_default
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')
    id_to_find = s.object_id
    # should return itself in the base case
    assert_equal(s, s.find_node(id_to_find))
  end

  def test_find_node_not_found
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')
    assert_equal(nil, s.find_node(-1))
  end

  def test_find_node_with_children
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')
    id_to_find = s.object_id
    # should return itself in the base case
    assert_equal(s, s.find_node(id_to_find))
  end

  def test_explain_sql_raising_an_error
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')
    config = { :adapter => 'mysql' }
    statement = NewRelic::Agent::Database::Statement.new('SELECT')
    statement.config = config
    statement.explainer = NewRelic::Agent::Instrumentation::ActiveRecord::EXPLAINER
    s.params = {:sql => statement}
    NewRelic::Agent::Database.expects(:get_connection).with(config).raises(RuntimeError.new("whee"))
    s.explain_sql
  end

  def test_explain_sql_can_handle_missing_config
    # If TT node came over from Resque child, might not be a Statement
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')
    s.params = { :sql => "SELECT * FROM galaxy" }
    s.explain_sql
  end

  def test_explain_sql_can_use_already_existing_plan
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')
    s.params = {
      :sql => "SELECT * FROM galaxy",
      :explain_plan => "EXPLAIN IT!"
    }

    assert_equal("EXPLAIN IT!", s.explain_sql)
  end

  def test_params_equal
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')
    assert_equal(nil, s.instance_eval { @params })

    params = {:foo => 'correct'}

    s.params = params
    assert_equal(params, s.instance_eval { @params })
  end

  def test_obfuscated_sql
    sql = 'select * from table where id = 1'
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')
    s[:sql] = NewRelic::Agent::Database::Statement.new(sql)
    assert_equal('select * from table where id = ?', s.obfuscated_sql)
  end

  def test_called_nodes_equals
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')
    assert_equal(nil, s.instance_eval { @called_nodes })
    s.called_nodes = [1, 2, 3]
    assert_equal([1, 2, 3], s.instance_eval { @called_nodes })
  end

  def test_parent_node_equals
    s = NewRelic::Agent::Transaction::TraceNode.new(Time.now, 'Custom/test/metric')
    assert_equal(nil, s.instance_eval { @parent_node })
    fake_node = mock('node')
    s.send(:parent_node=, fake_node)
    assert_equal(fake_node, s.parent_node)
  end
end
