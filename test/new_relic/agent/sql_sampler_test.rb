# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','data_container_tests'))

class NewRelic::Agent::SqlSamplerTest < Minitest::Test
  def setup
    agent = NewRelic::Agent.instance
    stats_engine = NewRelic::Agent::StatsEngine.new
    agent.stubs(:stats_engine).returns(stats_engine)
    @state = NewRelic::Agent::TransactionState.tl_get
    @state.reset
    @sampler = NewRelic::Agent::SqlSampler.new
    @connection = stub('ActiveRecord connection', :execute => 'result')
    NewRelic::Agent::Database.stubs(:get_connection).returns(@connection)
  end

  def teardown
    @state.reset
  end

  # Helpers for DataContainerTests

  def create_container
    NewRelic::Agent::SqlSampler.new
  end

  def populate_container(sampler, n)
    n.times do |i|
      sampler.on_start_transaction(@state, nil)
      sampler.notice_sql("SELECT * FROM test#{i}", "Database/test/select", {}, 1, @state)
      sampler.on_finishing_transaction(@state, 'txn')
    end
  end

  include NewRelic::DataContainerTests

  # Tests

  def test_on_start_transaction
    assert_nil @sampler.tl_transaction_data
    @sampler.on_start_transaction(@state, nil)
    refute_nil @sampler.tl_transaction_data
    @sampler.on_finishing_transaction(@state, 'txn')

    # Transaction clearing cleans this @state for us--we don't do it ourselves
    refute_nil @sampler.tl_transaction_data
  end

  def test_notice_sql_no_transaction
    assert_nil @sampler.tl_transaction_data
    @sampler.notice_sql("select * from test", "Database/test/select", nil, 10, @state)
  end

  def test_notice_sql
    @sampler.on_start_transaction(@state, nil)
    @sampler.notice_sql("select * from test", "Database/test/select", nil, 1.5, @state)
    @sampler.notice_sql("select * from test2", "Database/test2/select", nil, 1.3, @state)
    # this sql will not be captured
    @sampler.notice_sql("select * from test", "Database/test/select", nil, 0, @state)
    refute_nil @sampler.tl_transaction_data
    assert_equal 2, @sampler.tl_transaction_data.sql_data.size
  end

  def test_notice_sql_truncates_query
    @sampler.on_start_transaction(@state, nil)
    message = 'a' * 17_000
    @sampler.notice_sql(message, "Database/test/select", nil, 1.5, @state)
    assert_equal('a' * 16_381 + '...', @sampler.tl_transaction_data.sql_data[0].sql)
  end

  def test_save_slow_sql
    data = NewRelic::Agent::TransactionSqlData.new
    data.set_transaction_info("/c/a", 'guid')
    data.set_transaction_name("WebTransaction/Controller/c/a")
    data.sql_data.concat [
      NewRelic::Agent::SlowSql.new(NewRelic::Agent::Database::Statement.new("select * from test"), "Database/test/select", 1.5),
      NewRelic::Agent::SlowSql.new(NewRelic::Agent::Database::Statement.new("select * from test"), "Database/test/select", 1.2),
      NewRelic::Agent::SlowSql.new(NewRelic::Agent::Database::Statement.new("select * from test2"), "Database/test2/select", 1.1)
    ]
    @sampler.save_slow_sql data

    assert_equal 2, @sampler.sql_traces.size
  end

  def test_sql_aggregation
    query = "select * from test"
    slow_sql = NewRelic::Agent::SlowSql.new(NewRelic::Agent::Database::Statement.new(query), "Database/test/select", 1.2)

    sql_trace = NewRelic::Agent::SqlTrace.new(query, slow_sql, "tx_name", "uri")

    sql_trace.aggregate NewRelic::Agent::SlowSql.new(NewRelic::Agent::Database::Statement.new(query), "Database/test/select", 1.5), "slowest_tx_name", "slow_uri"
    sql_trace.aggregate NewRelic::Agent::SlowSql.new(NewRelic::Agent::Database::Statement.new(query), "Database/test/select", 1.1), "other_tx_name", "uri2"

    assert_equal 3, sql_trace.call_count
    assert_equal "slowest_tx_name", sql_trace.path
    assert_equal "slow_uri", sql_trace.url
    assert_equal 1.5, sql_trace.max_call_time
  end

  def test_harvest
    data = NewRelic::Agent::TransactionSqlData.new
    data.set_transaction_info("/c/a", 'guid')
    data.set_transaction_name("WebTransaction/Controller/c/a")
    data.sql_data.concat [NewRelic::Agent::SlowSql.new(NewRelic::Agent::Database::Statement.new("select * from test"), "Database/test/select", 1.5),
                          NewRelic::Agent::SlowSql.new(NewRelic::Agent::Database::Statement.new("select * from test"), "Database/test/select", 1.2),
                          NewRelic::Agent::SlowSql.new(NewRelic::Agent::Database::Statement.new("select * from test2"), "Database/test2/select", 1.1)]
    @sampler.save_slow_sql data

    sql_traces = @sampler.harvest!
    assert_equal 2, sql_traces.size
  end

  def test_harvest_should_not_take_more_than_10
    data = NewRelic::Agent::TransactionSqlData.new
    data.set_transaction_info("/c/a", 'guid')
    data.set_transaction_name("WebTransaction/Controller/c/a")
    15.times do |i|
      statement = NewRelic::Agent::Database::Statement.new("select * from test#{(i+97).chr}")
      data.sql_data << NewRelic::Agent::SlowSql.new(statement, "Database/test#{(i+97).chr}/select", i)
    end

    @sampler.save_slow_sql data
    result = @sampler.harvest!

    assert_equal(10, result.size)
    assert_equal(14, result.sort{|a,b| b.max_call_time <=> a.max_call_time}.first.total_call_time)
  end

  def test_harvest_should_aggregate_similar_queries
    data = NewRelic::Agent::TransactionSqlData.new
    data.set_transaction_info("/c/a", 'guid')
    data.set_transaction_name("WebTransaction/Controller/c/a")
    queries = [
               NewRelic::Agent::SlowSql.new(NewRelic::Agent::Database::Statement.new("select  * from test where foo in (1, 2)  "), "Database/test/select", 1.5),
               NewRelic::Agent::SlowSql.new(NewRelic::Agent::Database::Statement.new("select * from test where foo in (1,2, 3 ,4,  5,6, 'snausage')"), "Database/test/select", 1.2),
               NewRelic::Agent::SlowSql.new(NewRelic::Agent::Database::Statement.new("select * from test2 where foo in (1,2)"), "Database/test2/select", 1.1)
              ]
    data.sql_data.concat(queries)
    @sampler.save_slow_sql data

    sql_traces = @sampler.harvest!
    assert_equal 2, sql_traces.size
  end

  def test_harvest_should_collect_explain_plans
    @connection.expects(:execute).with("EXPLAIN select * from test") \
     .returns(dummy_mysql_explain_result({"header0" => 'foo0', "header1" => 'foo1', "header2" => 'foo2'}))
    @connection.expects(:execute).with("EXPLAIN select * from test2") \
     .returns(dummy_mysql_explain_result({"header0" => 'bar0', "header1" => 'bar1', "header2" => 'bar2'}))

    data = NewRelic::Agent::TransactionSqlData.new
    data.set_transaction_info("/c/a", 'guid')
    data.set_transaction_name("WebTransaction/Controller/c/a")
    explainer = NewRelic::Agent::Instrumentation::ActiveRecord::EXPLAINER
    config = { :adapter => 'mysql' }
    queries = [
               NewRelic::Agent::SlowSql.new(NewRelic::Agent::Database::Statement.new("select * from test", config, explainer),
                                            "Database/test/select", 1.5),
               NewRelic::Agent::SlowSql.new(NewRelic::Agent::Database::Statement.new("select * from test", config, explainer),
                                            "Database/test/select", 1.2),
               NewRelic::Agent::SlowSql.new(NewRelic::Agent::Database::Statement.new("select * from test2", config, explainer),
                                            "Database/test2/select", 1.1)
              ]
    data.sql_data.concat(queries)
    @sampler.save_slow_sql data
    sql_traces = @sampler.harvest!.sort_by(&:total_call_time).reverse

    assert_equal(["header0", "header1", "header2"],
                 sql_traces[0].params[:explain_plan][0].sort)
    assert_equal(["header0", "header1", "header2"],
                 sql_traces[1].params[:explain_plan][0].sort)
    assert_equal(["foo0", "foo1", "foo2"],
                 sql_traces[0].params[:explain_plan][1][0].sort)
    assert_equal(["bar0", "bar1", "bar2"],
                 sql_traces[1].params[:explain_plan][1][0].sort)
  end

  def test_sql_trace_should_include_transaction_guid
    txn_sampler = NewRelic::Agent::TransactionSampler.new
    txn_sampler.start_builder(@state, Time.now)
    @sampler.on_start_transaction(@state, Time.now, 'a uri')

    assert_equal(NewRelic::Agent.instance.transaction_sampler.tl_builder.sample.guid,
                 NewRelic::Agent.instance.sql_sampler.tl_transaction_data.guid)
  end

  def test_should_not_collect_explain_plans_when_disabled
    with_config(:'transaction_tracer.explain_enabled' => false) do
      data = NewRelic::Agent::TransactionSqlData.new
      data.set_transaction_info("/c/a", 'guid')
      data.set_transaction_name("WebTransaction/Controller/c/a")
      queries = [
                 NewRelic::Agent::SlowSql.new(NewRelic::Agent::Database::Statement.new("select * from test"),
                                              "Database/test/select", 1.5)
                ]
      data.sql_data.concat(queries)
      @sampler.save_slow_sql data
      sql_traces = @sampler.harvest!
      assert_equal(nil, sql_traces[0].params[:explain_plan])
    end
  end

  def test_should_not_collect_anything_when_record_sql_is_off
    sampler = NewRelic::Agent.agent.sql_sampler

    settings = {
      :'slow_sql.enabled'    => true,
      :'slow_sql.record_sql' => 'off'
    }

    with_config(settings) do
      in_transaction do
        sql = "SELECT * FROM test"
        metric_name = "Database/test/select"
        sampler.notice_sql(sql, metric_name, {}, 10)
      end
    end

    traces = sampler.harvest!
    assert_empty(traces)
  end

  def test_sql_id_fits_in_a_mysql_int_11
    statement = NewRelic::Agent::Database::Statement.new("select * from test")
    sql_trace = NewRelic::Agent::SqlTrace.new("select * from test",
            NewRelic::Agent::SlowSql.new(statement,
                "Database/test/select", 1.2),
        "tx_name", "uri")

    assert(-2147483648 <= sql_trace.sql_id, "sql_id too small")
    assert( 2147483647 >= sql_trace.sql_id, "sql_id too large")
  end

  def test_sends_obfuscated_queries_when_configured
    with_config(:'transaction_tracer.record_sql' => 'obfuscated') do
      data = NewRelic::Agent::TransactionSqlData.new
      data.set_transaction_info("/c/a", 'guid')
      data.set_transaction_name("WebTransaction/Controller/c/a")
      data.sql_data.concat([NewRelic::Agent::SlowSql.new(NewRelic::Agent::Database::Statement.new("select * from test where foo = 'bar'"),
                                                         "Database/test/select", 1.5),
                            NewRelic::Agent::SlowSql.new(NewRelic::Agent::Database::Statement.new("select * from test where foo in (1,2,3,4,5)"),
                                                         "Database/test/select", 1.2)])
      @sampler.save_slow_sql(data)
      sql_traces = @sampler.harvest!.sort_by(&:total_call_time).reverse

      assert_equal('select * from test where foo = ?', sql_traces[0].sql)
      assert_equal('select * from test where foo in (?,?,?,?,?)', sql_traces[1].sql)
    end
  end

  def test_sends_obfuscated_queries_when_configured_via_slow_sql_settings
    settings = {
      :'slow_sql.record_sql'           => 'obfuscated',
      :'transaction_tracer.record_sql' => 'raw'
    }
    with_config(settings) do
      data = NewRelic::Agent::TransactionSqlData.new
      data.set_transaction_info("/c/a", 'guid')
      data.set_transaction_name("WebTransaction/Controller/c/a")
      data.sql_data.concat([NewRelic::Agent::SlowSql.new(NewRelic::Agent::Database::Statement.new("select * from test where foo = 'bar'"),
                                                         "Database/test/select", 1.5),
                            NewRelic::Agent::SlowSql.new(NewRelic::Agent::Database::Statement.new("select * from test where foo in (1,2,3,4,5)"),
                                                         "Database/test/select", 1.2)])
      @sampler.save_slow_sql(data)
      sql_traces = @sampler.harvest!.sort_by(&:total_call_time).reverse

      assert_equal('select * from test where foo = ?', sql_traces[0].sql)
      assert_equal('select * from test where foo in (?,?,?,?,?)', sql_traces[1].sql)
    end
  end

  def test_does_not_over_obfuscate_queries_for_postgres
    with_config(:'transaction_tracer.record_sql' => 'obfuscated') do
      sampler = NewRelic::Agent.agent.sql_sampler

      in_transaction do
        sql = %Q[INSERT INTO "items" ("name", "price") VALUES ('continuum transfunctioner', 100000) RETURNING "id"]
        sampler.notice_sql sql, "Database/test/insert", {:adapter => "postgres"}, 1.23
      end
      sql_traces = sampler.harvest!
      assert_equal(%Q[INSERT INTO "items" ("name", "price") VALUES (?, ?) RETURNING "id"], sql_traces[0].sql)
    end
  end

  def test_takes_slowest_samples
    data = NewRelic::Agent::TransactionSqlData.new
    data.set_transaction_info("/c/a", 'guid')
    data.set_transaction_name("WebTransaction/Controller/c/a")

    count = NewRelic::Agent::SqlSampler::MAX_SAMPLES * 2
    durations = (0...count).to_a.shuffle
    durations.each do |i|
      data.sql_data << NewRelic::Agent::SlowSql.new(NewRelic::Agent::Database::Statement.new("SELECT * FROM table#{i}"), "Database/table#{i}/select", i)
    end

    @sampler.save_slow_sql(data)
    sql_traces = @sampler.harvest!

    harvested_durations = sql_traces.map(&:total_call_time).sort
    expected_durations  = durations.sort.last(10)

    assert_equal expected_durations, harvested_durations
  end

  def test_can_directly_marshal_traces_for_pipe_transmittal
    with_config(:'transaction_tracer.explain_enabled' => false) do
      data = NewRelic::Agent::TransactionSqlData.new
      explainer = NewRelic::Agent::Instrumentation::ActiveRecord::EXPLAINER
      data.sql_data.concat([NewRelic::Agent::SlowSql.new(NewRelic::Agent::Database::Statement.new("select * from test", {}, explainer),
                                                         "Database/test/select", 1.5)])
      @sampler.save_slow_sql(data)
      sql_traces = @sampler.harvest!

      Marshal.dump(sql_traces)
    end
  end

  def test_to_collector_array
    with_config(:'transaction_tracer.explain_enabled' => false) do
      data = NewRelic::Agent::TransactionSqlData.new
      data.set_transaction_info("/c/a", 'guid')
      data.set_transaction_name("WebTransaction/Controller/c/a")
      data.sql_data.concat([NewRelic::Agent::SlowSql.new(NewRelic::Agent::Database::Statement.new("select * from test"),
                                                         "Database/test/select", 1.5)])
      @sampler.save_slow_sql(data)
      sql_traces = @sampler.harvest!

      marshaller = NewRelic::Agent::NewRelicService::JsonMarshaller.new
      params = "eJyrrgUAAXUA+Q==\n"

      expected = [ 'WebTransaction/Controller/c/a', '/c/a', 526336943,
                   'select * from test', 'Database/test/select',
                   1, 1500, 1500, 1500, params ]

      assert_equal expected, sql_traces[0].to_collector_array(marshaller.default_encoder)
    end
  end

  def test_to_collector_array_with_bad_values
    statement = NewRelic::Agent::Database::Statement.new("query")
    slow = NewRelic::Agent::SlowSql.new(statement, "transaction", Rational(12, 1))
    trace = NewRelic::Agent::SqlTrace.new("query", slow, "path", "uri")
    trace.call_count = Rational(10, 1)
    trace.instance_variable_set(:@sql_id, "1234")

    marshaller = NewRelic::Agent::NewRelicService::JsonMarshaller.new
    params = "eJyrrgUAAXUA+Q==\n"

    expected = [ "path", "uri", 1234, "query", "transaction",
                 10, 12000, 12000, 12000, params]

    assert_equal expected, trace.to_collector_array(marshaller.default_encoder)
  end

  def test_merge_without_existing_trace
    query = "select * from test"
    statement = NewRelic::Agent::Database::Statement.new(query, {})
    slow_sql = NewRelic::Agent::SlowSql.new(statement, "Database/test/select", 1)
    trace = NewRelic::Agent::SqlTrace.new(query, slow_sql, "txn_name", "uri")

    @sampler.merge!([trace])
    assert_equal(trace, @sampler.sql_traces[query])
  end

  def test_merge_with_existing_trace
    query = "select * from test"
    statement = NewRelic::Agent::Database::Statement.new(query, {})
    slow_sql0 = NewRelic::Agent::SlowSql.new(statement, "Database/test/select", 1)
    slow_sql1 = NewRelic::Agent::SlowSql.new(statement, "Database/test/select", 2)

    trace0 = NewRelic::Agent::SqlTrace.new(query, slow_sql0, "txn_name", "uri")
    trace1 = NewRelic::Agent::SqlTrace.new(query, slow_sql1, "txn_name", "uri")

    @sampler.merge!([trace0])
    @sampler.merge!([trace1])

    aggregated_trace = @sampler.sql_traces[query]
    assert_equal(2, aggregated_trace.call_count)
    assert_equal(3, aggregated_trace.total_call_time)
  end

  def test_on_finishing_transaction_with_busted_transaction_state_does_not_crash
    state = NewRelic::Agent::TransactionState.tl_get
    @sampler.on_finishing_transaction(state, "whatever", Time.now)
  end

  def test_caps_collection_of_unique_statements
    data = NewRelic::Agent::TransactionSqlData.new
    data.set_transaction_info("/c/a", 'guid')
    data.set_transaction_name("WebTransaction/Controller/c/a")

    count = NewRelic::Agent::SqlSampler::MAX_SAMPLES + 1
    count.times do |i|
      statement = NewRelic::Agent::Database::Statement.new("SELECT * FROM table#{i}", {})
      data.sql_data << NewRelic::Agent::SlowSql.new(statement, "Database/table#{i}/select", i)
    end

    @sampler.save_slow_sql(data)

    assert_equal NewRelic::Agent::SqlSampler::MAX_SAMPLES, @sampler.sql_traces.size
  end
end
