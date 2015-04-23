# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.join(File.dirname(__FILE__), 'database.rb')
require File.join(File.dirname(__FILE__), 'sequel_helpers.rb')

if Sequel.const_defined?( :MAJOR ) &&
      ( Sequel::MAJOR > 3 ||
        Sequel::MAJOR == 3 && Sequel::MINOR >= 37 )

require 'newrelic_rpm'

class SequelPluginTest < Minitest::Test
  include SequelHelpers

  def expected_metrics_for_operation(operation)
    [
      ["Datastore/statement/#{product_name}/Post/#{operation}", "dummy"],
      "Datastore/statement/#{product_name}/Post/#{operation}",
      "Datastore/operation/#{product_name}/#{operation}",
      "Datastore/#{product_name}/allWeb",
      "Datastore/allWeb",
      "Datastore/#{product_name}/all",
      "Datastore/all",
      "dummy",
      "Apdex"
    ]
  end

  def test_sequel_model_instrumentation_is_loaded
    assert Post.respond_to?( :trace_execution_scoped )
  end

  def test_model_enumerator_generates_metrics
    in_web_transaction { Post.all }

    assert_datastore_metrics_recorded_exclusive(expected_metrics_for_operation(:all))
  end

  def test_model_index_operator_generates_metrics
    in_web_transaction { Post[11] }

    assert_datastore_metrics_recorded_exclusive(expected_metrics_for_operation(:get))
  end

  def test_model_create_method_generates_metrics
    in_web_transaction do
      Post.create( :title => 'The Thing', :content => 'A wicked short story.' )
    end

    assert_datastore_metrics_recorded_exclusive(expected_metrics_for_operation(:create))
  end

  def test_model_update_method_generates_metrics
    in_web_transaction do
      post = NewRelic::Agent.disable_all_tracing do
        Post.create( :title => 'All The Things', :content => 'A story about beans.' )
      end

      post.update( :title => 'A Lot of the Things' )
    end

    assert_datastore_metrics_recorded_exclusive(expected_metrics_for_operation(:update))
  end

  def test_model_update_all_method_generates_metrics
    in_web_transaction do
      post = NewRelic::Agent.disable_all_tracing do
        Post.create( :title => 'All The Things', :content => 'A nicer story than yours.' )
      end

      post.update_all( :title => 'A Whole Hell of a Lot of the Things' )
    end

    assert_datastore_metrics_recorded_exclusive(expected_metrics_for_operation(:update_all))
  end

  def test_model_update_except_method_generates_metrics
    in_web_transaction do
      post = NewRelic::Agent.disable_all_tracing do
        Post.create( :title => 'All The Things', :content => 'A story.' )
      end

      post.update_except( {:title => 'A Bit More of the Things'} )
    end

    assert_datastore_metrics_recorded_exclusive(expected_metrics_for_operation(:update_except))
  end

  def test_model_update_fields_method_generates_metrics
    in_web_transaction do
      post = NewRelic::Agent.disable_all_tracing do
        Post.create( :title => 'All The Things', :content => 'A venal short story.' )
      end

      post.update_fields( {:title => 'A Plethora of Things'}, [:title] )
    end

    assert_datastore_metrics_recorded_exclusive(expected_metrics_for_operation(:update_fields))
  end

  def test_model_update_only_method_generates_metrics
    in_web_transaction do
      post = NewRelic::Agent.disable_all_tracing do
        Post.create( :title => 'All The Things', :content => 'A meandering short story.' )
      end

      post.update_only( {:title => 'A Lot of the Things'}, :title )
    end

    assert_datastore_metrics_recorded_exclusive(expected_metrics_for_operation(:update_only))
  end

  def test_model_save_method_generates_metrics
    in_web_transaction do
      post = NewRelic::Agent.disable_all_tracing do
        Post.new( :title => 'An Endless Lot Full of Things',
                  :content => 'A lingering long story.' )
      end

      post.save
    end

   assert_datastore_metrics_recorded_exclusive(expected_metrics_for_operation(:save))
  end

  def test_model_delete_method_generates_metrics
    in_web_transaction do
      post = NewRelic::Agent.disable_all_tracing do
        Post.create( :title => 'All The Things', :content => 'A nice short story.' )
      end

      post.delete
    end

    assert_datastore_metrics_recorded_exclusive(expected_metrics_for_operation(:delete))
  end

  def test_model_destroy_method_generates_metrics
    in_web_transaction do
      post = NewRelic::Agent.disable_all_tracing do
        Post.create( :title => 'Most of the Things', :content => 'Another short story.' )
      end

      post.destroy
    end

    assert_datastore_metrics_recorded_exclusive(expected_metrics_for_operation(:destroy))
  end

  def test_model_destroy_uses_the_class_name_for_the_metric
    in_web_transaction do
      post = NewRelic::Agent.disable_all_tracing do
        Post.create( :title => 'Some of the Things', :content => 'A shorter story.' )
      end

      post.destroy
    end

    assert_datastore_metrics_recorded_exclusive(expected_metrics_for_operation(:destroy))
  end

  def test_slow_queries_get_an_explain_plan
    with_config( :'transaction_tracer.explain_threshold' => -0.01,
                 :'transaction_tracer.record_sql' => 'raw' ) do
      node = last_node_for do
        Post[11]
      end
      assert_match %r{select \* from `posts` where `id` = 11}i, node.params[:sql]
      assert_node_has_explain_plan( node )
    end
  end

  def test_sql_is_recorded_in_tt_for_non_select
    with_config(:'transaction_tracer.record_sql' => 'raw') do
      node = last_node_for do
        Post.create(:title => 'title', :content => 'content')
      end
      assert_match %r{insert into `posts` \([^\)]*\) values \([^\)]*\)}i, node.params[:sql]
    end
  end

  def test_no_explain_plans_with_single_threaded_connection
    connect_opts = DB.opts
    single_threaded_db = Sequel.connect(connect_opts.merge(:single_threaded => true))
    create_tables(single_threaded_db)
    model_class = Class.new(Sequel::Model(single_threaded_db[:posts]))

    with_config(:'transaction_tracer.explain_threshold' => -0.01,
                :'transaction_tracer.record_sql' => 'raw') do
      node = last_node_for do
        model_class[11]
      end
      assert_match %r{select \* from `posts` where `id` = 11}i, node.params[:sql]
      assert_equal([], node.params[:explain_plan], "Should not capture explain plan with single-threaded connection pool")
    end
  end

  def test_queries_can_get_explain_plan_with_obfuscated_sql
    config = {
      :'transaction_tracer.explain_threshold' => -0.01,
      :'transaction_tracer.record_sql' => 'obfuscated'
    }
    with_config(config) do
      node = last_node_for(:record_sql => :obfuscated) do
        Post[11]
      end
      assert_match %r{select \* from `posts` where `id` = \?}i, node.params[:sql]
      assert_node_has_explain_plan( node )
    end
  end

  def test_notices_sql_with_proper_metric_name_for_select
    config = {
      :'transaction_tracer.explain_threshold' => -0.01,
      :'transaction_tracer.record_sql' => 'obfuscated'
    }
    with_config(config) do
      in_web_transaction { Post.all }
      expected_metric_name = "Datastore/operation/#{product_name}/select"
      recorded_metric_names = NewRelic::Agent.agent.sql_sampler.sql_traces.values.map(&:database_metric_name)
      assert recorded_metric_names.include? expected_metric_name
    end
  end
end

else
  puts "Skipping tests in #{__FILE__} because unsupported Sequel version"
end
