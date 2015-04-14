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
    @trace.root_segment.end_trace(@start_time)

    filter = NewRelic::Agent.instance.attribute_filter
    @fake_attributes = NewRelic::Agent::Transaction::Attributes.new(filter)

    @trace.agent_attributes = @fake_attributes
    @trace.custom_attributes = @fake_attributes
    @trace.intrinsic_attributes = @fake_attributes
  end

  def test_start_time
    assert_equal @start_time, @trace.start_time
  end

  def test_segment_count
    assert_equal 0, @trace.segment_count
  end

  def test_sample_id_is_the_object_id
    assert_equal @trace.object_id, @trace.sample_id
  end

  def test_create_segment_increases_segment_count
    @trace.create_segment(0.0, 'foo')
    assert_equal 1, @trace.segment_count
  end

  def test_duration_is_the_root_segment_duration
    assert_equal @trace.duration, @trace.root_segment.duration
  end

  def test_create_segment
    result = @trace.create_segment(0.0, 'goo')
    assert_equal 0.0, result.entry_timestamp
    assert_equal 'goo', result.metric_name
  end

  def test_each_segment_delegates_to_root_segment
    block = Proc.new {}
    @trace.root_segment.expects(:each_segment)
    @trace.each_segment(&block)
  end

  def test_collector_array_contains_start_time
    expected = NewRelic::Helper.time_to_millis(@start_time)
    assert_collector_array_contains(:start_time, expected)
  end

  def test_root_segment
    assert_equal 0.0, @trace.root_segment.entry_timestamp
    assert_equal "ROOT", @trace.root_segment.metric_name
  end

  def test_collector_array_contains_root_segment_duration
    @trace.root_segment.end_trace(1)
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
    @trace.synthetics_resource_id = '31415926'
    assert_collector_array_contains(:synthetics_resource_id, '31415926')
  end

  def test_synthetics_resource_id_gets_coerced_to_a_string
    @trace.synthetics_resource_id = 31415926
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

  def test_trace_tree_contains_serialized_root_segment
    assert_trace_tree_contains(:root_segment, @trace.root_segment.to_array)
  end

  def test_trace_tree_contains_attributes
    @fake_attributes.add(:foo, 'bar')

    expected = {
      'agentAttributes' => { :foo => 'bar' },
      'customAttributes' => { :foo => 'bar' },
      'intrinsics' => { :foo => 'bar' }
    }

    assert_trace_tree_contains(:attributes, expected)
  end

  def test_to_collector_array_encodes_trace_tree_with_given_encoder
    fake_encoder = mock
    fake_encoder.expects(:encode).with(@trace.trace_tree)
    @trace.to_collector_array(fake_encoder)
  end

  def assert_trace_tree_contains(key, expected)
    indices = [
      :start_time,
      :unused_legacy_request_params,
      :unused_legacy_custom_params,
      :root_segment,
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
      :forced?,
      :xray_session_id,
      :synthetics_resource_id
    ]

    encoder = NewRelic::Agent::NewRelicService::Encoders::Identity
    assert_equal expected, @trace.to_collector_array(encoder)[indices.index(key)]
  end
end
