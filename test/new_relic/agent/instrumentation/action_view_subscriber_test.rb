# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

if defined?(::Rails)

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/instrumentation/action_view_subscriber'

class NewRelic::Agent::Instrumentation::ActionViewSubscriberTest < Minitest::Test
  def setup
    @subscriber = NewRelic::Agent::Instrumentation::ActionViewSubscriber.new
    @stats_engine = NewRelic::Agent.instance.stats_engine
  end

  def teardown
    NewRelic::Agent.instance.stats_engine.clear_stats
  end

  def test_records_metrics_for_simple_template
    params = { :identifier => '/root/app/views/model/index.html.erb' }
    t0 = Time.now
    Time.stubs(:now).returns(t0, t0, t0 + 2, t0 + 2)

    @subscriber.start('render_template.action_view', :id, params)
    @subscriber.start('!render_template.action_view', :id,
                      :virtual_path => 'model/index')
    @subscriber.finish('!render_template.action_view', :id,
                       :virtual_path => 'model/index')
    @subscriber.finish('render_template.action_view', :id, params)

    metric = @stats_engine.lookup_stats('View/model/index.html.erb/Rendering')
    assert_equal(1, metric.call_count)
    assert_equal(2.0, metric.total_call_time)
  end

  def test_records_metrics_for_simple_file
    params = { :identifier => '/root/something.txt' }
    t0 = Time.now
    Time.stubs(:now).returns(t0, t0, t0 + 2, t0 + 2)

    @subscriber.start('render_template.action_view', :id, params)
    @subscriber.start('!render_template.action_view', :id,
                      :virtual_path => nil)
    @subscriber.finish('!render_template.action_view', :id,
                       :virtual_path => nil)
    @subscriber.finish('render_template.action_view', :id, params)

    metric = @stats_engine.lookup_stats('View/file/Rendering')
    assert_equal(1, metric.call_count)
    assert_equal(2.0, metric.total_call_time)
  end

  def test_records_metrics_for_simple_inline
    params = { :identifier => 'inline template' }
    t0 = Time.now
    Time.stubs(:now).returns(t0, t0, t0 + 2, t0 + 2)

    @subscriber.start('render_template.action_view', :id, params)
    @subscriber.start('!render_template.action_view', :id,
                      :virtual_path => nil)
    @subscriber.finish('!render_template.action_view', :id,
                       :virtual_path => nil)
    @subscriber.finish('render_template.action_view', :id, params)

    metric = @stats_engine.lookup_stats('View/inline template/Rendering')
    assert_equal(1, metric.call_count)
    assert_equal(2.0, metric.total_call_time)
  end

  def test_records_metrics_for_simple_text
    params = { :identifier => 'text template' }
    t0 = Time.now
    Time.stubs(:now).returns(t0, t0 + 2)

    @subscriber.start('render_template.action_view', :id, params)
    @subscriber.finish('render_template.action_view', :id, params)

    metric = @stats_engine.lookup_stats('View/text template/Rendering')
    assert_equal(1, metric.call_count)
    assert_equal(2.0, metric.total_call_time)
  end

  def test_records_metrics_for_simple_partial
    params = { :identifier => '/root/app/views/model/_form.html.erb' }
    t0 = Time.now
    Time.stubs(:now).returns(t0, t0, t0 + 2, t0 + 2)

    @subscriber.start('render_partial.action_view', :id, params)
    @subscriber.start('!render_template.action_view', :id,
                      :virtual_path => 'model/_form')
    @subscriber.finish('!render_template.action_view', :id,
                       :virtual_path => 'model/_form')
    @subscriber.finish('render_partial.action_view', :id, params)

    metric = @stats_engine.lookup_stats('View/model/_form.html.erb/Partial')
    assert_equal(1, metric.call_count)
    assert_equal(2.0, metric.total_call_time)
  end

  def test_records_metrics_for_simple_collection
    params = { :identifier => '/root/app/views/model/_user.html.erb' }
    t0 = Time.now
    Time.stubs(:now).returns(t0, t0, t0 + 2, t0 + 2)

    @subscriber.start('render_collection.action_view', :id, params)
    @subscriber.start('!render_template.action_view', :id,
                      :virtual_path => 'model/_user')
    @subscriber.finish('!render_template.action_view', :id,
                       :virtual_path => 'model/_user')
    @subscriber.finish('render_collection.action_view', :id, params)

    metric = @stats_engine.lookup_stats('View/model/_user.html.erb/Partial')
    assert_equal(1, metric.call_count)
    assert_equal(2.0, metric.total_call_time)
  end

  def test_records_metrics_for_layout
    t0 = Time.now
    Time.stubs(:now).returns(t0, t0 + 2)

    @subscriber.start('!render_template.action_view', :id,
                      :virtual_path => 'layouts/application')
    @subscriber.finish('!render_template.action_view', :id,
                       :virtual_path => 'layouts/application')

    metric = @stats_engine.lookup_stats('View/layouts/application/Rendering')
    assert_equal(1, metric.call_count)
    assert_equal(2.0, metric.total_call_time)
  end

  def test_records_scoped_metric
    params = { :identifier => '/root/app/views/model/index.html.erb' }

    in_transaction('test_txn') do
      @subscriber.start('render_template.action_view', :id, params)
      @subscriber.start('!render_template.action_view', :id,
                        :virtual_path => 'model/index')
      @subscriber.finish('!render_template.action_view', :id,
                         :virtual_path => 'model/index')
      @subscriber.finish('render_template.action_view', :id, params)
    end

    metric = @stats_engine.lookup_stats('View/model/index.html.erb/Rendering',
                                        'test_txn')
    assert_equal(1, metric.call_count)
  end

  def test_records_nothing_if_tracing_disabled
    params = { :identifier => '/root/app/views/model/_user.html.erb' }

    NewRelic::Agent.disable_all_tracing do
      @subscriber.start('render_collection.action_view', :id, params)
      @subscriber.finish('render_collection.action_view', :id, params)
    end

    metric = @stats_engine.lookup_stats('View/model/_user.html.erb/Partial')
    assert_nil metric
  end

  def test_creates_txn_segment_for_simple_render
    params = { :identifier => '/root/app/views/model/index.html.erb' }

    in_transaction do
      @subscriber.start('render_template.action_view', :id, params)
      @subscriber.start('!render_template.action_view', :id,
                        :virtual_path => 'model/index')
      @subscriber.finish('!render_template.action_view', :id,
                         :virtual_path => 'model/index')
      @subscriber.finish('render_template.action_view', :id, params)
    end

    last_segment = nil
    sampler = NewRelic::Agent.instance.transaction_sampler
    sampler.last_sample.root_segment.each_segment{|s| last_segment = s }
    NewRelic::Agent.shutdown

    assert_equal('View/model/index.html.erb/Rendering',
                 last_segment.metric_name)
  end

  def test_creates_nested_partial_segment_within_render_segment
    in_transaction do
      @subscriber.start('render_template.action_view', :id,
                        :identifier => 'model/index.html.erb')
      @subscriber.start('!render_template.action_view', :id,
                        :virtual_path => 'model/index')
      @subscriber.start('render_partial.action_view', :id,
                        :identifier => '/root/app/views/model/_list.html.erb')
      @subscriber.start('!render_template.action_view', :id,
                        :virtual_path => 'model/_list')
      @subscriber.finish('!render_template.action_view', :id,
                         :virtual_path => 'model/_list')
      @subscriber.finish('render_partial.action_view', :id,
                         :identifier => '/root/app/views/model/_list.html.erb')
      @subscriber.finish('!render_template.action_view', :id,
                           :virtual_path => 'model/index')
      @subscriber.finish('render_template.action_view', :id,
                         :identifier => 'model/index.html.erb')
    end

    sampler = NewRelic::Agent.instance.transaction_sampler
    template_segment = sampler.last_sample.root_segment.called_segments[0].called_segments[0]
    partial_segment = template_segment.called_segments[0]

    assert_equal('View/model/index.html.erb/Rendering',
                 template_segment.metric_name)
    assert_equal('View/model/_list.html.erb/Partial',
                 partial_segment.metric_name)
  end

  def test_creates_nodes_for_each_in_a_collection_event
    in_transaction do
      @subscriber.start('render_collection.action_view', :id,
                        :identifier => '/root/app/views/model/_list.html.erb',
                        :count => 3)
      @subscriber.start('!render_template.action_view', :id,
                        :virtual_path => 'model/_list')
      @subscriber.finish('!render_template.action_view', :id,
                        :virtual_path => 'model/_list')
      @subscriber.start('!render_template.action_view', :id,
                        :virtual_path => 'model/_list')
      @subscriber.finish('!render_template.action_view', :id,
                        :virtual_path => 'model/_list')
      @subscriber.start('!render_template.action_view', :id,
                        :virtual_path => 'model/_list')
      @subscriber.finish('!render_template.action_view', :id,
                        :virtual_path => 'model/_list')
      @subscriber.finish('render_collection.action_view', :id,
                         :identifier => '/root/app/views/model/_list.html.erb',
                         :count => 3)
    end

    sampler = NewRelic::Agent.instance.transaction_sampler
    partial_segments = sampler.last_sample.root_segment.called_segments[0].called_segments

    assert_equal 3, partial_segments.size
    assert_equal('View/model/_list.html.erb/Partial',
                 partial_segments[0].metric_name)
  end
end if ::Rails::VERSION::MAJOR.to_i >= 4

else
  puts "Skipping tests in #{__FILE__} because Rails is unavailable"
end
