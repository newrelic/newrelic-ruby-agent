# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

class TiltInstrumentationTest < Minitest::Test
  include MultiverseHelpers

  def setup
    @stats_engine = NewRelic::Agent.instance.stats_engine
  end

  def teardown
    NewRelic::Agent.instance.stats_engine.clear_stats
  end

  def haml_template
    Tilt.new('test.haml')
  end

  def haml_initialize_metric
    'Tilt::HamlTemplate#initialize'
  end

  ### Initialize Tests ###
  def test_records_metrics_for_haml_template
    in_transaction do
      haml_template
    end

    expected = { call_count: 1 }
    assert_metrics_recorded(haml_initialize_metric => expected)
  end

  def test_records_metrics_for_erb_template
    in_transaction do
      Tilt.new('test.erb')
    end

    expected = { call_count: 1 }
    assert_metrics_recorded('Tilt::ERBTemplate#initialize' => expected)
  end

  def test_records_metrics_for_nested_templates
    in_transaction do
      Tilt.new('layout.haml').render {
        haml_template
      }
    end

    expected = { call_count: 2 }
    assert_metrics_recorded(haml_initialize_metric => expected)
  end

  def test_records_scoped_metric
    test_transaction = 'test_txn'

    in_transaction(test_transaction) do
      haml_template
    end

    expected = { :call_count => 1 }
    assert_metrics_recorded(
      [haml_initialize_metric, test_transaction] => expected
    )
  end

  def test_records_transaction_level_error
    skip 'Not sure how to raise or capure an error here. Need to determine what should happen...'
    exception_class = TypeError
    txn = nil
    Tilt::Template.any_instance.stubs(:initialize).raises(exception_class)

    in_transaction do |test_txn|
      txn = test_txn
      haml_template
    end

    assert_transaction_noticed_error txn, exception_class.name
  end

  def test_records_nothing_if_tracing_disabled
    NewRelic::Agent.disable_all_tracing do
      in_transaction do
        haml_template
      end
    end

    assert_metrics_not_recorded(haml_initialize_metric)
  end

  def test_creates_transaction_node_for_initialize
    in_transaction do
      haml_template
    end

    last_node = nil
    last_transaction_trace.root_node.each_node{|s| last_node = s }
    NewRelic::Agent.shutdown

    assert_equal(haml_initialize_metric,
                 last_node.metric_name)
  end

  # Tilt doesn't exactly use partials, but it does accept blocks to a render node
  # Which effectively do the same thing as yielding partials
  # See: https://code.tutsplus.com/tutorials/ruby-for-newbies-the-tilt-gem--net-20027
  # Under heading, "Yielding for More Power"
  # I liked this test idea and am leaving it here to add with the render changes
  def test_creates_nested_partial_node_within_render_node
  end
end
