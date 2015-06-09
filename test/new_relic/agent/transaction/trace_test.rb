# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../../test_helper.rb', __FILE__)
require 'new_relic/agent/transaction/trace'

class NewRelic::Agent::Transaction::TraceTest < Minitest::Test
  def setup
    freeze_time
    @start_time = Time.now
    @trace = NewRelic::Agent::Transaction::Trace.new(@start_time)
    @trace.root_node.end_trace(@start_time)

    filter = NewRelic::Agent.instance.attribute_filter
    @fake_attributes = NewRelic::Agent::Transaction::Attributes.new(filter)

    @trace.attributes = @fake_attributes
  end

  def test_start_time
    assert_equal @start_time, @trace.start_time
  end

  def test_node_count
    assert_equal 0, @trace.node_count
  end

  def test_sample_id_is_the_object_id
    assert_equal @trace.object_id, @trace.sample_id
  end

  def test_create_node_increases_node_count
    @trace.create_node(0.0, 'foo')
    assert_equal 1, @trace.node_count
  end

  def test_duration_is_the_root_node_duration
    assert_equal @trace.duration, @trace.root_node.duration
  end

  def test_create_node
    result = @trace.create_node(0.0, 'goo')
    assert_equal 0.0, result.entry_timestamp
    assert_equal 'goo', result.metric_name
  end

  def test_each_node_delegates_to_root_node
    block = Proc.new {}
    @trace.root_node.expects(:each_node)
    @trace.each_node(&block)
  end

  def test_collector_array_contains_start_time
    expected = NewRelic::Helper.time_to_millis(@start_time)
    assert_collector_array_contains(:start_time, expected)
  end

  def test_root_node
    assert_equal 0.0, @trace.root_node.entry_timestamp
    assert_equal "ROOT", @trace.root_node.metric_name
  end

  def test_prepare_to_send_returns_self
    result = @trace.prepare_to_send!
    assert_equal @trace, result
  end

  def test_prepare_to_send_returns_self_if_already_prepared
    @trace.prepare_to_send!

    result = @trace.prepare_to_send!
    assert_equal @trace, result
  end

  def test_prepare_to_send_is_idempotent
    NewRelic::Agent::Database.stubs(:should_record_sql?).returns true
    @trace.expects(:collect_explain_plans!).once
    @trace.expects(:prepare_sql_for_transmission!).once
    @trace.prepare_to_send!
    @trace.prepare_to_send!
  end

  def test_prepare_to_send_handles_sql_and_does_not_strip_if_should_record_sql_is_true
    NewRelic::Agent::Database.stubs(:should_record_sql?).returns true
    @trace.expects(:collect_explain_plans!).once
    @trace.expects(:prepare_sql_for_transmission!).once
    @trace.expects(:strip_sql!).never
    @trace.prepare_to_send!
  end

  def test_prepare_to_send_strips_and_does_not_handle_sql_if_should_record_sql_is_false
    NewRelic::Agent::Database.stubs(:should_record_sql?).returns false
    @trace.expects(:collect_explain_plans!).never
    @trace.expects(:prepare_sql_for_transmission!).never
    @trace.expects(:strip_sql!).once
    @trace.prepare_to_send!
  end

  def test_prepare_to_send_collects_explain_plans
    node = @trace.create_node(0.0, 'has_sql')
    node.stubs(:duration).returns(2)
    node.stubs(:explain_sql).returns('')
    node[:sql] = ''

    @trace.root_node.add_called_node(node)

    with_config(:'transaction_tracer.explain_threshold' => 1) do
      @trace.prepare_to_send!
    end

    assert node[:explain_plan]
  end

  def test_prepare_to_send_prepares_sql_for_transmission
    NewRelic::Agent::Database.stubs(:record_sql_method).returns :obfuscated

    node = @trace.create_node(0.0, 'has_sql')
    node.stubs(:duration).returns(2)
    node[:sql] = "select * from pelicans where name = '1337807';"
    @trace.root_node.add_called_node(node)

    @trace.prepare_to_send!
    assert_equal "select * from pelicans where name = ?;", node[:sql]
  end

  def test_prepare_to_send_strips_sql
    NewRelic::Agent::Database.stubs(:should_record_sql?).returns false
    node = @trace.create_node(0.0, 'has_sql')
    node.stubs(:duration).returns(2)
    node.stubs(:explain_sql).returns('')
    node[:sql] = 'select * from pelicans;'

    @trace.root_node.add_called_node(node)
    @trace.prepare_to_send!

    refute node[:sql]
  end

  def test_collect_explain_plans!
    node = @trace.create_node(0.0, 'has_sql')
    node.stubs(:duration).returns(2)
    node.stubs(:explain_sql).returns('')
    node[:sql] = ''

    @trace.root_node.add_called_node(node)

    with_config(:'transaction_tracer.explain_threshold' => 1) do
      @trace.collect_explain_plans!
    end

    assert node[:explain_plan]
  end

  def test_collect_explain_plans_does_not_attach_explain_plans_if_duration_is_too_short
    node = @trace.create_node(0.0, 'has_sql')
    node.stubs(:duration).returns(1)
    node.stubs(:explain_sql).returns('')
    node[:sql] = ''

    @trace.root_node.add_called_node(node)

    with_config(:'transaction_tracer.explain_threshold' => 2) do
      @trace.collect_explain_plans!
    end

    refute node[:explain_plan]
  end

  def test_collect_explain_plans_does_not_attach_explain_plans_without_sql
    node = @trace.create_node(0.0, 'nope_sql')
    node.stubs(:duration).returns(2)
    node.stubs(:explain_sql).returns('')
    node[:sql] = nil

    @trace.root_node.add_called_node(node)

    with_config(:'transaction_tracer.explain_threshold' => 1) do
      @trace.collect_explain_plans!
    end

    refute node[:explain_plan]
  end

  def test_collect_explain_plans_does_not_attach_explain_plans_if_db_says_not_to
    node = @trace.create_node(0.0, 'has_sql')
    node.stubs(:duration).returns(2)
    node.stubs(:explain_sql).returns('')
    node[:sql] = ''

    NewRelic::Agent::Database.stubs(:should_collect_explain_plans?).returns(false)

    @trace.root_node.add_called_node(node)

    with_config(:'transaction_tracer.explain_threshold' => 1) do
      @trace.collect_explain_plans!
    end

    refute node[:explain_plan]
  end

  def test_prepare_sql_for_transmission_obfuscates_sql_if_record_sql_method_is_obfuscated
    NewRelic::Agent::Database.stubs(:record_sql_method).returns :obfuscated

    node = @trace.create_node(0.0, 'has_sql')
    node[:sql] = "select * from pelicans where name = '1337807';"
    @trace.root_node.add_called_node(node)

    @trace.prepare_sql_for_transmission!
    assert_equal "select * from pelicans where name = ?;", node[:sql]
  end

  def test_prepare_sql_for_transmission_does_not_modify_sql_if_record_sql_method_is_raw
    NewRelic::Agent::Database.stubs(:record_sql_method).returns :raw

    node = @trace.create_node(0.0, 'has_sql')
    node[:sql] = NewRelic::Agent::Database::Statement.new "select * from pelicans where name = '1337807';"
    @trace.root_node.add_called_node(node)

    @trace.prepare_sql_for_transmission!
    assert_equal "select * from pelicans where name = '1337807';", node[:sql]
  end

  def test_prepare_sql_for_transmission_removes_sql_if_record_sql_method_is_off
    NewRelic::Agent::Database.stubs(:record_sql_method).returns :off

    node = @trace.create_node(0.0, 'has_sql')
    node[:sql] = "select * from pelicans where name = '1337807';"
    @trace.root_node.add_called_node(node)

    @trace.prepare_sql_for_transmission!
    refute node[:sql]
  end

  def test_strip_sql!
    node = @trace.create_node(0.0, 'has_sql')
    node.stubs(:duration).returns(2)
    node.stubs(:explain_sql).returns('')
    node[:sql] = 'select * from pelicans;'

    @trace.root_node.add_called_node(node)
    @trace.strip_sql!

    refute node[:sql]
  end

  def test_collector_array_contains_root_node_duration
    @trace.root_node.end_trace(1)
    assert_collector_array_contains(:duration, 1000)
  end

  def test_collector_array_contains_transaction_name
    @trace.transaction_name = 'zork'
    assert_collector_array_contains(:transaction_name, 'zork')
  end

  def test_transaction_name_gets_coerced_into_a_string
    @trace.transaction_name = 1337807
    assert_collector_array_contains(:transaction_name, '1337807')
  end

  def test_collector_array_contains_uri
    @trace.uri = 'http://windows95tips.com/'
    assert_collector_array_contains(:uri, 'http://windows95tips.com/')
  end

  def test_uri_gets_coerced_into_a_string
    @trace.uri = 95
    assert_collector_array_contains(:uri, '95')
  end

  def test_collector_array_contains_trace_tree
    assert_collector_array_contains(:trace_tree, @trace.trace_tree)
  end

  def test_collector_array_contains_guid
    @trace.guid = 'DEADBEEF8BADF00D'
    assert_collector_array_contains(:guid, 'DEADBEEF8BADF00D')
  end

  def test_guid_gets_coerced_into_a_string
    @trace.guid = 42
    assert_collector_array_contains(:guid, '42')
  end

  def test_collector_array_contains_nil_for_reserved
    assert_collector_array_contains(:reserved, nil)
  end

  def test_collector_array_contains_forced_true_if_in_an_xray_session
    @trace.xray_session_id = 7
    assert_collector_array_contains(:forced?, true)
  end

  def test_collector_array_contains_forced_false_if_not_in_an_xray_session
    @trace.xray_session_id = nil
    assert_collector_array_contains(:forced?, false)
  end

  def test_collector_array_contains_xray_session_id
    @trace.xray_session_id = 112357
    assert_collector_array_contains(:xray_session_id, 112357)
  end

  def test_xray_session_id_gets_coerced_to_an_integer
    @trace.xray_session_id = '112357'
    assert_collector_array_contains(:xray_session_id, 112357)
  end

  def test_xray_session_id_does_not_coerce_nil_to_an_integer
    @trace.xray_session_id = nil
    assert_collector_array_contains(:xray_session_id, nil)
  end

  def test_collector_array_contains_synthetics_resource_id
    @fake_attributes.add_intrinsic_attribute(:synthetics_resource_id, '31415926')
    assert_collector_array_contains(:synthetics_resource_id, '31415926')
  end

  def test_to_collector_array_encodes_trace_tree_with_given_encoder
    fake_encoder = mock
    fake_encoder.expects(:encode).with(@trace.trace_tree)
    @trace.to_collector_array(fake_encoder)
  end

  def test_synthetics_resource_id_gets_coerced_to_a_string
    @fake_attributes.add_intrinsic_attribute(:synthetics_resource_id, 31415926)
    assert_collector_array_contains(:synthetics_resource_id, '31415926')
  end

  def test_trace_tree_coerces_start_time_to_a_float
    assert_kind_of Float, @trace.trace_tree.first
  end

  def test_trace_tree_includes_start_time
    assert_trace_tree_contains(:start_time, @start_time.to_f)
  end

  def test_trace_tree_includes_unused_legacy_request_params
    assert_trace_tree_contains(:unused_legacy_request_params, {})
  end

  def test_trace_tree_includes_unused_legacy_custom_params
    assert_trace_tree_contains(:unused_legacy_custom_params, {})
  end

  def test_trace_tree_contains_serialized_root_node
    assert_trace_tree_contains(:root_node, @trace.root_node.to_array)
  end

  def test_trace_tree_contains_attributes
    @fake_attributes.add_agent_attribute(:foo, 'bar', NewRelic::Agent::AttributeFilter::DST_ALL)
    @fake_attributes.add_intrinsic_attribute(:foo, 'bar')
    @fake_attributes.merge_custom_attributes(:foo => 'bar')

    expected = {
      'agentAttributes' => { :foo => 'bar' },
      'userAttributes'  => { "foo" => 'bar' },
      'intrinsics'      => { :foo => 'bar' }
    }

    assert_trace_tree_contains(:attributes, expected)
  end

  def assert_trace_tree_contains(key, expected)
    indices = [
      :start_time,
      :unused_legacy_request_params,
      :unused_legacy_custom_params,
      :root_node,
      :attributes
    ]

    assert_equal expected, @trace.trace_tree[indices.index(key)]
  end

  def assert_collector_array_contains(key, expected)
    indices = [
      :start_time,
      :duration,
      :transaction_name,
      :uri,
      :trace_tree,
      :guid,
      :reserved,
      :forced?,
      :xray_session_id,
      :synthetics_resource_id
    ]

    encoder = NewRelic::Agent::NewRelicService::Encoders::Identity
    assert_equal expected, @trace.to_collector_array(encoder)[indices.index(key)]
  end
end
