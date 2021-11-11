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
    Tilt.new('test.haml').render
  end

  def haml_render_metric
    'Tilt::HamlTemplate#render'
  end

  ### Render Tests ###
  def test_records_metrics_for_haml_template
    in_transaction do
      haml_template
    end

    expected = { call_count: 1 }
    assert_metrics_recorded(haml_render_metric => expected)
  end

  def test_records_metrics_for_erb_template
    in_transaction do
      Tilt.new('test.erb').render
    end

    expected = { call_count: 1 }
    assert_metrics_recorded('Tilt::ERBTemplate#render' => expected)
  end

  def test_records_metrics_for_nested_templates
    in_transaction do
      Tilt.new('layout.haml').render {
        haml_template
      }
    end

    expected = { call_count: 2 }
    assert_metrics_recorded(haml_render_metric => expected)
  end

  def test_records_scoped_metric
    test_transaction = 'test_txn'

    in_transaction(test_transaction) do
      haml_template
    end

    expected = { :call_count => 1 }
    assert_metrics_recorded(
      [haml_render_metric, test_transaction] => expected
    )
  end

  def test_records_transaction_level_error
    exception_class = TypeError
    txn = nil
    Tilt::Template.any_instance.stubs(:evaluate).raises(exception_class)

    in_transaction do |test_txn|
      txn = test_txn
      begin
        haml_template
      rescue
        # this is what we wanted
      end
    end

    assert_transaction_noticed_error txn, exception_class.name
  end

  def test_records_nothing_if_tracing_disabled
    NewRelic::Agent.disable_all_tracing do
      in_transaction do
        haml_template
      end
    end

    assert_metrics_not_recorded(haml_render_metric)
  end

  def test_creates_transaction_node_for_render
    in_transaction do
      haml_template
    end

    last_node = nil
    last_transaction_trace.root_node.each_node{|s| last_node = s }
    NewRelic::Agent.shutdown

    assert_equal(haml_render_metric,
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
