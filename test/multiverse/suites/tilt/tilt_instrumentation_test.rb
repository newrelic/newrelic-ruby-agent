# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class TiltInstrumentationTest < Minitest::Test
  def setup
    @stats_engine = NewRelic::Agent.instance.stats_engine
  end

  def teardown
    NewRelic::Agent.instance.stats_engine.clear_stats
  end

  def haml_template
    Tilt.new('test.haml').render
  end

  def haml_render_metric(filename = 'test.haml')
    if NewRelic::Helper.version_satisfied?(Haml::VERSION, '>=', '6.0.0')
      "View/Haml::Template/#{filename}/Rendering"
    else
      "View/Tilt::HamlTemplate/#{filename}/Rendering"
    end
  end

  ### Tilt::Template#render tests ###
  def test_records_metrics_for_haml_template
    in_transaction do
      haml_template
    end

    expected = {call_count: 1}

    assert_metrics_recorded(haml_render_metric => expected)
  end

  def test_records_metrics_for_erb_template
    in_transaction do
      Tilt.new('test.erb').render
    end

    expected = {call_count: 1}

    assert_metrics_recorded('View/Tilt::ERBTemplate/test.erb/Rendering' => expected)
  end

  def test_records_metrics_for_nested_templates
    in_transaction do
      Tilt.new('layout.haml').render {
        haml_template
      }
    end

    expected = {call_count: 1}

    assert_metrics_recorded(haml_render_metric('layout.haml') => expected)
    assert_metrics_recorded(haml_render_metric => expected)
  end

  def test_records_scoped_metric
    test_transaction = 'test_txn'

    in_transaction(test_transaction) do
      haml_template
    end

    expected = {:call_count => 1}

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
    last_transaction_trace.root_node.each_node { |s| last_node = s }
    NewRelic::Agent.shutdown

    assert_equal(haml_render_metric,
      last_node.metric_name)
  end

  def test_creates_nested_partial_node_within_render_node
    in_transaction do
      Tilt.new('layout.haml').render { haml_template }
    end
    template_node = last_transaction_trace.root_node.children[0].children[0]
    partial_node = template_node.children[0]

    assert_equal(haml_render_metric('layout.haml'),
      template_node.metric_name)
    assert_equal(haml_render_metric,
      partial_node.metric_name)
  end

  ### File name parsing tests ###
  def call_create_filename_for_metric(filename)
    Class.new.extend(
      NewRelic::Agent::Instrumentation::Tilt
    ).create_filename_for_metric(
      filename
    )
  end

  def non_nested_path
    'views/index.html.erb'
  end

  def long_path_prefix
    '/Users/rubyist/dev/my_sinatra_app/'
  end

  def nested_path
    'blogs/index.html.erb'
  end

  def long_non_nested_path
    long_path_prefix + non_nested_path
  end

  def long_nested_path
    long_path_prefix + 'views/' + nested_path
  end

  def with_fake_sinatra(&blk)
    sinatra_dummy_module = Module.new
    sinatra_dummy_class = Class.new(Object)
    with_constant_defined(:'::Sinatra', sinatra_dummy_module) do
      with_constant_defined(:'::Sinatra::Base', sinatra_dummy_class) do
        yield
      end
    end
  end

  def test_returns_file_if_sinatra_not_defined
    assert_equal(
      call_create_filename_for_metric(non_nested_path),
      non_nested_path
    )
  end

  def test_returns_nested_route_with_sinatra_defined
    with_fake_sinatra do
      assert_equal(
        call_create_filename_for_metric(long_nested_path),
        nested_path
      )
    end
  end

  def test_returns_non_nested_route_with_sinatra_defined
    with_fake_sinatra do
      assert_equal(
        call_create_filename_for_metric(long_non_nested_path),
        non_nested_path
      )
    end
  end

  def test_returns_file_if_no_method_error_raised
    String.any_instance.stubs(:split).raises(NoMethodError)

    assert_equal(
      call_create_filename_for_metric(long_non_nested_path),
      long_non_nested_path
    )
    String.any_instance.unstub(:split)
  end
end
