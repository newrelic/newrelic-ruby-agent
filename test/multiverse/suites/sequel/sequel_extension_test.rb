# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.join(File.dirname(__FILE__), 'database.rb')

if Sequel.const_defined?( :MAJOR ) &&
      ( Sequel::MAJOR > 3 ||
        Sequel::MAJOR == 3 && Sequel::MINOR >= 37 )

require 'newrelic_rpm'

class SequelExtensionTest < Minitest::Test

  def setup
    super

    DB.extension :newrelic_instrumentation

    NewRelic::Agent.manual_start
    NewRelic::Agent.instance.transaction_sampler.reset!
    NewRelic::Agent.instance.stats_engine.clear_stats

    @posts = DB[:posts]

    NewRelic::Agent.disable_all_tracing do
      post_id = @posts.insert( :title => 'All The Things', :content => 'A nice short story.' )
      @post = @posts[:id => post_id]
    end
  end

  def teardown
    super

    NewRelic::Agent.shutdown
  end

  def expected_metrics_for_operation(operation)
    [
      ["Datastore/operation/SQLite/#{operation}", "dummy"],
      "Datastore/operation/SQLite/#{operation}",
      "Datastore/SQLite/allWeb",
      "Datastore/allWeb",
      "Datastore/SQLite/all",
      "Datastore/all",
      "dummy",
      "Apdex"
    ]
  end

  def test_all
    in_web_transaction { @posts.all }

    assert_metrics_recorded_exclusive(expected_metrics_for_operation(:select))
  end

  def test_find
    in_web_transaction do 
      @posts[:id => 11]
    end

    assert_metrics_recorded_exclusive(expected_metrics_for_operation(:select))
  end

  def test_model_create_method_generates_metrics
    in_web_transaction do
      @posts.insert( :title => 'The Thing', :content => 'A wicked short story.' )
    end

    assert_metrics_recorded_exclusive(expected_metrics_for_operation(:insert))
  end

  def test_update
    in_web_transaction do
      @posts.where(:id => @post[:id]).update( :title => 'A Lot of the Things' )
    end
    
    assert_metrics_recorded_exclusive(expected_metrics_for_operation(:update))
  end

  def test_delete
    in_web_transaction do
      @posts.where(:id => @post[:id]).delete
    end

    assert_metrics_recorded_exclusive(expected_metrics_for_operation(:delete))
  end

  def test_slow_queries_get_an_explain_plan
    with_config( :'transaction_tracer.explain_threshold' => -0.01,
                 :'transaction_tracer.record_sql' => 'raw' ) do
      segment = last_segment_for do
        @posts[:id => 11]
      end
      assert_match %r{select \* from `posts` where \(?`id` = 11\)?( limit 1)?}i, segment.params[:sql]
      assert_segment_has_explain_plan( segment )
    end
  end


  def test_queries_can_get_explain_plan_with_obfuscated_sql
    config = {
      :'transaction_tracer.explain_threshold' => -0.01,
      :'transaction_tracer.record_sql' => 'obfuscated'
    }
    with_config(config) do
      segment = last_segment_for(:record_sql => :obfuscated) do
        @posts[:id => 11]
      end
      assert_match %r{select \* from `posts` where \(?`id` = \?\)?}i, segment.params[:sql]
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
