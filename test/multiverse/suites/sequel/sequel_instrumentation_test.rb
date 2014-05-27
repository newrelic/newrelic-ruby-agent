# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.join(File.dirname(__FILE__), 'database.rb')

if Sequel.const_defined?( :MAJOR ) &&
      ( Sequel::MAJOR > 3 ||
        Sequel::MAJOR == 3 && Sequel::MINOR >= 37 )

require 'newrelic_rpm'
require File.join(File.dirname(__FILE__), '..', '..', '..', 'agent_helper')

class NewRelic::Agent::Instrumentation::SequelInstrumentationTest < Minitest::Test

  def setup
    super

    DB.extension :newrelic_instrumentation

    NewRelic::Agent.manual_start
    NewRelic::Agent.instance.transaction_sampler.reset!
    NewRelic::Agent.instance.stats_engine.clear_stats
  end

  def teardown
    super

    NewRelic::Agent.shutdown
  end

  def test_sequel_database_instrumentation_is_loaded
    assert DB.respond_to?( :primary_metric_for )
  end

  def test_sequel_model_instrumentation_is_loaded
    assert Post.respond_to?( :trace_execution_scoped )
  end

  def test_model_enumerator_generates_metrics
    in_web_transaction { Post.all }

    assert_remote_service_metrics
    assert_metrics_recorded([
      "Database/SQL/select",
      "ActiveRecord/all",
      "ActiveRecord/#{Post.name}/all"
    ])
  end

  def test_model_index_operator_generates_metrics
    in_web_transaction { Post[11] }

    assert_remote_service_metrics
    assert_metrics_recorded([
      "Database/SQL/select",
      "ActiveRecord/all",
      "ActiveRecord/#{Post.name}/get"
    ])
  end

  def test_model_create_method_generates_metrics
    in_web_transaction do
      Post.create( :title => 'The Thing', :content => 'A wicked short story.' )
    end

    assert_remote_service_metrics
    assert_metrics_recorded([
      'Database/SQL/insert',
      'ActiveRecord/all',
      "ActiveRecord/#{Post.name}/create"
    ])
  end

  def test_model_update_method_generates_metrics
    in_web_transaction do
      post = Post.create( :title => 'All The Things', :content => 'A story about beans.' )
      post.update( :title => 'A Lot of the Things' )
    end

    assert_remote_service_metrics
    assert_metrics_recorded([
      'Database/SQL/update',
      'ActiveRecord/all',
      "ActiveRecord/#{Post.name}/update"
    ])
  end

  def test_model_update_all_method_generates_metrics
    in_web_transaction do
      post = Post.create( :title => 'All The Things', :content => 'A nicer story than yours.' )
      post.update_all( :title => 'A Whole Hell of a Lot of the Things' )
    end

    assert_remote_service_metrics
    assert_metrics_recorded([
      "Database/SQL/update",
      "ActiveRecord/all",
      "ActiveRecord/#{Post.name}/update_all"
    ])
  end

  def test_model_update_except_method_generates_metrics
    in_web_transaction do
      post = Post.create( :title => 'All The Things', :content => 'A story.' )
      post.update_except( {:title => 'A Bit More of the Things'} )
    end

    assert_remote_service_metrics
    assert_metrics_recorded([
      "Database/SQL/update",
      "ActiveRecord/all",
      "ActiveRecord/#{Post.name}/update_except"
    ])
  end

  def test_model_update_fields_method_generates_metrics
    in_web_transaction do
      post = Post.create( :title => 'All The Things', :content => 'A venal short story.' )
      post.update_fields( {:title => 'A Plethora of Things'}, [:title] )
    end

    assert_remote_service_metrics
    assert_metrics_recorded([
      "Database/SQL/update",
      "ActiveRecord/all",
      "ActiveRecord/#{Post.name}/update_fields"
    ])
  end

  def test_model_update_only_method_generates_metrics
    in_web_transaction do
      post = Post.create( :title => 'All The Things', :content => 'A meandering short story.' )
      post.update_only( {:title => 'A Lot of the Things'}, :title )
    end

    assert_remote_service_metrics
    assert_metrics_recorded([
      "Database/SQL/update",
      "ActiveRecord/all",
      "ActiveRecord/#{Post.name}/update_only"
    ])
  end

  def test_model_save_method_generates_metrics
    in_web_transaction do
      post = Post.new( :title => 'An Endless Lot Full of Things',
                       :content => 'A lingering long story.' )
      post.save
    end

    assert_remote_service_metrics
    assert_metrics_recorded([
      "Database/SQL/insert",
      "ActiveRecord/all",
      "ActiveRecord/#{Post.name}/save"
    ])
  end

  def test_model_delete_method_generates_metrics
    in_web_transaction do
      post = Post.create( :title => 'All The Things', :content => 'A nice short story.' )
      post.delete
    end

    assert_remote_service_metrics
    assert_metrics_recorded([
      "Database/SQL/delete",
      "ActiveRecord/all",
      "ActiveRecord/#{Post.name}/delete"
    ])
  end

  def test_model_destroy_method_generates_metrics
    in_web_transaction do
      post = Post.create( :title => 'Most of the Things', :content => 'Another short story.' )
      post.destroy
    end

    assert_remote_service_metrics
    assert_metrics_recorded([
      "Database/SQL/delete",
      "ActiveRecord/all",
      "ActiveRecord/#{Post.name}/destroy"
    ])
  end

  def test_model_destroy_uses_the_class_name_for_the_metric
    in_web_transaction do
      author = Author.create( :name => 'Marlon Forswytthe', :login => 'mfors' )
      author.destroy
    end

    assert_remote_service_metrics
    assert_metrics_recorded([
      "Database/SQL/delete",
      "ActiveRecord/all",
      "ActiveRecord/#{Author.name}/destroy"
    ])
  end

  def test_slow_queries_get_an_explain_plan
    with_config( :'transaction_tracer.explain_threshold' => -0.01,
                 :'transaction_tracer.record_sql' => 'raw' ) do
      segment = last_segment_for do
        Post[11]
      end
      assert_match %r{select \* from `posts` where `id` = 11}i, segment.params[:sql]
      assert_segment_has_explain_plan( segment )
    end
  end

  def test_no_explain_plans_with_single_threaded_connection
    connect_opts = DB.opts
    single_threaded_db = Sequel.connect(connect_opts.merge(:single_threaded => true))
    create_tables(single_threaded_db)
    model_class = Class.new(Sequel::Model(single_threaded_db[:posts]))

    with_config(:'transaction_tracer.explain_threshold' => -0.01,
                :'transaction_tracer.record_sql' => 'raw') do
      segment = last_segment_for do
        model_class[11]
      end
      assert_match %r{select \* from `posts` where `id` = 11}i, segment.params[:sql]
      assert_equal([], segment.params[:explain_plan], "Should not capture explain plan with single-threaded connection pool")
    end
  end

  def test_queries_can_get_explain_plan_with_obfuscated_sql
    config = {
      :'transaction_tracer.explain_threshold' => -0.01,
      :'transaction_tracer.record_sql' => 'obfuscated'
    }
    with_config(config) do
      segment = last_segment_for(:record_sql => :obfuscated) do
        Post[11]
      end
      assert_match %r{select \* from `posts` where `id` = \?}i, segment.params[:sql]
      assert_segment_has_explain_plan( segment )
    end
  end


  #
  # Helpers
  #

  # Pattern to match the column headers of a Sqlite explain plan
  SQLITE_EXPLAIN_PLAN_COLUMNS_RE =
    %r{\|addr\s*\|opcode\s*\|p1\s*\|p2\s*\|p3\s*\|p4\s*\|p5\s*\|comment\s*\|}

  # This is particular to sqlite plans currently. To abstract it up, we'd need to
  # be able to specify a flavor (e.g., :sqlite, :postgres, :mysql, etc.)
  def assert_segment_has_explain_plan( segment, msg=nil )
    msg = "Expected #{segment.inspect} to have an explain plan"
    assert_block( msg ) { segment.params[:explain_plan].join =~ SQLITE_EXPLAIN_PLAN_COLUMNS_RE }
  end

  def assert_remote_service_metrics
    engine = NewRelic::Agent.instance.stats_engine
    if (jruby?)
      assert engine.metrics.none? {|s| s.start_with?("RemoteService/")}, "Sqlite on JRuby doesn't report adapter right for this metric. Why's it here?"
    else
      assert_includes engine.metrics, "RemoteService/sql/sqlite/localhost"
    end
  end

  def last_segment_for(options={})
      in_transaction('sandwiches/index') do
        yield
      end
      sample = NewRelic::Agent.instance.transaction_sampler.last_sample
      sample.prepare_to_send!
      last_segment(sample)
  end

  def last_segment(txn_sample)
    l_segment = nil
    txn_sample.root_segment.each_segment do |segment|
      l_segment = segment
    end
    l_segment
  end

end

else
  puts "Skipping tests in #{__FILE__} because unsupported Sequel version"
end
