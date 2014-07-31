# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..',
                                   'test_helper'))
require 'new_relic/agent/database'
class NewRelic::Agent::DatabaseTest < Minitest::Test
  def setup
    @explainer = NewRelic::Agent::Instrumentation::ActiveRecord::EXPLAINER
  end

  def teardown
    NewRelic::Agent::Database::Obfuscator.instance.reset
  end

  def test_adapter_from_config_string
    config = { :adapter => 'mysql' }
    assert_equal('mysql', NewRelic::Agent::Database.adapter_from_config(config))
  end

  def test_adapter_from_config_symbol
    config = { :adapter => :mysql }
    assert_equal('mysql', NewRelic::Agent::Database.adapter_from_config(config))
  end

  def test_adapter_from_config_uri_jdbc_postgresql
    config = { :uri=>"jdbc:postgresql://host/database?user=posgres" }
    assert_equal('postgresql', NewRelic::Agent::Database.adapter_from_config(config))
  end

  def test_adapter_from_config_uri_jdbc_mysql
    config = { :uri=>"jdbc:mysql://host/database" }
    assert_equal('mysql', NewRelic::Agent::Database.adapter_from_config(config))
  end

  def test_adapter_from_config_uri_jdbc_sqlite
    config = { :uri => "jdbc:sqlite::memory" }
    assert_equal('sqlite', NewRelic::Agent::Database.adapter_from_config(config))
  end

  def test_explain_sql_select_with_mysql_connection
    config = {:adapter => 'mysql'}
    config.default('val')
    sql = 'SELECT foo'
    connection = mock('mysql connection')
    plan = {
      "select_type"=>"SIMPLE", "key_len"=>nil, "table"=>"blogs", "id"=>"1",
      "possible_keys"=>nil, "type"=>"ALL", "Extra"=>"", "rows"=>"2",
      "ref"=>nil, "key"=>nil
    }
    result = mock('explain plan')
    result.expects(:each_hash).yields(plan)
    # two rows, two columns
    connection.expects(:execute).with('EXPLAIN SELECT foo').returns(result)
    NewRelic::Agent::Database.stubs(:get_connection).returns(connection)
    result = NewRelic::Agent::Database.explain_sql(sql, config, &@explainer)
    assert_equal(plan.keys.sort, result[0].sort)
    assert_equal(plan.values.compact.sort, result[1][0].compact.sort)
  end

  def test_explain_sql_select_with_mysql2_connection_sequel
    config = { :adapter => 'mysql2' }
    config.default('val')
    sql = 'SELECT * FROM items'

    # Sequel returns explain plans to us as one giant preformatted string rather
    # than individual rows.
    plan_string = [
      "+--+-----------+-----+----+-------------+---+-------+---+----+-----+",
      "|id|select_type|table|type|possible_keys|key|key_len|ref|rows|Extra|",
      "+--+-----------+-----+----+-------------+---+-------+---+----+-----+",
      "| 1|SIMPLE     |items|ALL |             |   |       |   |   3|     |",
      "+--+-----------+-----+----+-------------+---+-------+---+----+-----+"
    ].join("\n")

    connection = mock('mysql connection')
    connection.expects(:execute).with('EXPLAIN SELECT * FROM items').returns(plan_string)
    NewRelic::Agent::Database.stubs(:get_connection).returns(connection)
    result = NewRelic::Agent::Database.explain_sql(sql, config, &@explainer)
    assert_nil(result[0])
    assert_equal([plan_string], result[1])
  end

  def test_explain_sql_select_with_mysql_connection_sequel
    config = { :adapter => 'mysql' }
    config.default('val')
    sql = 'SELECT * FROM items'

    # Sequel returns explain plans to us as one giant preformatted string rather
    # than individual rows.
    plan_string = [
      "+--+-----------+-----+----+-------------+---+-------+---+----+-----+",
      "|id|select_type|table|type|possible_keys|key|key_len|ref|rows|Extra|",
      "+--+-----------+-----+----+-------------+---+-------+---+----+-----+",
      "| 1|SIMPLE     |items|ALL |             |   |       |   |   3|     |",
      "+--+-----------+-----+----+-------------+---+-------+---+----+-----+"
    ].join("\n")

    connection = mock('mysql connection')
    connection.expects(:execute).with('EXPLAIN SELECT * FROM items').returns(plan_string)
    NewRelic::Agent::Database.stubs(:get_connection).returns(connection)
    result = NewRelic::Agent::Database.explain_sql(sql, config, &@explainer)
    assert_nil(result[0])
    assert_equal([plan_string], result[1])
  end

  def test_explain_sql_select_with_mysql2_connection
    config = {:adapter => 'mysql2'}
    config.default('val')
    sql = 'SELECT foo'
    connection = mock('mysql connection')

    plan_fields = ["select_type", "key_len", "table", "id", "possible_keys", "type", "Extra", "rows", "ref", "key"]
    plan_row =    ["SIMPLE",       nil,      "blogs", "1",   nil,            "ALL",  "",      "2",     nil,   nil ]

    result = mock('explain plan')
    result.expects(:fields).returns(plan_fields)
    result.expects(:each).yields(plan_row)

    # two rows, two columns
    connection.expects(:execute).with('EXPLAIN SELECT foo').returns(result)
    NewRelic::Agent::Database.stubs(:get_connection).returns(connection)
    result = NewRelic::Agent::Database.explain_sql(sql, config, &@explainer)
    assert_equal(plan_fields.sort, result[0].sort)
    assert_equal(plan_row.compact.sort, result[1][0].compact.sort)
  end

  def test_explain_sql_one_select_with_pg_connection
    config = {:adapter => 'postgresql'}
    config.default('val')
    sql = 'select count(id) from blogs limit 1'
    connection = stub('pg connection', :disconnect! => true)
    plan = [{"QUERY PLAN"=>"Limit  (cost=11.75..11.76 rows=1 width=4)"},
            {"QUERY PLAN"=>"  ->  Aggregate  (cost=11.75..11.76 rows=1 width=4)"},
            {"QUERY PLAN"=>"        ->  Seq Scan on blogs  (cost=0.00..11.40 rows=140 width=4)"}]
    connection.expects(:execute).returns(plan)
    NewRelic::Agent::Database.stubs(:get_connection).returns(connection)
    assert_equal([['QUERY PLAN'],
                  [["Limit  (cost=11.75..11.76 rows=1 width=4)"],
                   ["  ->  Aggregate  (cost=11.75..11.76 rows=1 width=4)"],
                   ["        ->  Seq Scan on blogs  (cost=0.00..11.40 rows=140 width=4)"]]],
                 NewRelic::Agent::Database.explain_sql(sql, config, &@explainer))
  end

  def test_explain_sql_one_select_with_pg_connection_string
    config = {:adapter => 'postgresql'}
    config.default('val')
    sql = 'select count(id) from blogs limit 1'
    connection = stub('pg connection', :disconnect! => true)
    plan = "Limit  (cost=11.75..11.76 rows=1 width=4)
  ->  Aggregate  (cost=11.75..11.76 rows=1 width=4)
        ->  Seq Scan on blogs  (cost=0.00..11.40 rows=140 width=4)"

    connection.expects(:execute).returns(plan)
    NewRelic::Agent::Database.stubs(:get_connection).returns(connection)
    assert_equal([['QUERY PLAN'],
                  [["Limit  (cost=11.75..11.76 rows=1 width=4)"],
                   ["  ->  Aggregate  (cost=11.75..11.76 rows=1 width=4)"],
                   ["        ->  Seq Scan on blogs  (cost=0.00..11.40 rows=140 width=4)"]]],
                 NewRelic::Agent::Database.explain_sql(sql, config, &@explainer))
  end

  def test_explain_sql_obfuscates_for_postgres
    config = {:adapter => 'postgresql'}
    config.default('val')
    sql = "SELECT * FROM blogs WHERE blogs.id=1234 AND blogs.title='sensitive text'"
    connection = stub('pg connection', :disconnect! => true)
    plan = [{"QUERY PLAN"=>" Index Scan using blogs_pkey on blogs  (cost=0.00..8.27 rows=1 width=540)"},
            {"QUERY PLAN"=>"   Index Cond: (id = 1234)"},
            {"QUERY PLAN"=>"   Filter: ((title)::text = 'sensitive text'::text)"}]
    connection.expects(:execute).returns(plan)
    NewRelic::Agent::Database.stubs(:get_connection).returns(connection)
    with_config(:'transaction_tracer.record_sql' => 'obfuscated') do
      assert_equal([['QUERY PLAN'],
                    [[" Index Scan using blogs_pkey on blogs  (cost=0.00..8.27 rows=1 width=540)"],
                     ["   Index Cond: ?"],
                     ["   Filter: ?"]]],
                   NewRelic::Agent::Database.explain_sql(sql, config, &@explainer))
    end
  end

  def test_explain_sql_does_not_obfuscate_if_record_sql_raw
    config = {:adapter => 'postgresql'}
    config.default('val')
    sql = "SELECT * FROM blogs WHERE blogs.id=1234 AND blogs.title='sensitive text'"
    connection = stub('pg connection', :disconnect! => true)
    plan = [{"QUERY PLAN"=>" Index Scan using blogs_pkey on blogs  (cost=0.00..8.27 rows=1 width=540)"},
            {"QUERY PLAN"=>"   Index Cond: (id = 1234)"},
            {"QUERY PLAN"=>"   Filter: ((title)::text = 'sensitive text'::text)"}]
    connection.expects(:execute).returns(plan)
    NewRelic::Agent::Database.stubs(:get_connection).returns(connection)
    with_config(:'transaction_tracer.record_sql' => 'raw') do
      assert_equal([['QUERY PLAN'],
                    [[" Index Scan using blogs_pkey on blogs  (cost=0.00..8.27 rows=1 width=540)"],
                     ["   Index Cond: (id = 1234)"],
                     ["   Filter: ((title)::text = 'sensitive text'::text)"]]],
                   NewRelic::Agent::Database.explain_sql(sql, config, &@explainer))
    end
  end

  def test_explain_sql_select_with_sqlite_connection
    config = {:adapter => 'sqlite'}
    config.default('val')
    sql = 'SELECT foo'
    connection = mock('sqlite connection')
    plan = [
      {"addr"=>0, "opcode"=>"Trace", "p1"=>0, "p2"=>0, "p3"=>0, "p4"=>"", "p5"=>"00", "comment"=>nil, 0=>0, 1=>"Trace", 2=>0, 3=>0, 4=>0, 5=>"", 6=>"00", 7=>nil},
      {"addr"=>1, "opcode"=>"Goto",  "p1"=>0, "p2"=>5, "p3"=>0, "p4"=>"", "p5"=>"00", "comment"=>nil, 0=>1, 1=>"Goto",  2=>0, 3=>5, 4=>0, 5=>"", 6=>"00", 7=>nil},
      {"addr"=>2, "opcode"=>"String8", "p1"=>0, "p2"=>1, "p3"=>0, "p4"=>"foo", "p5"=>"00", "comment"=>nil, 0=>2, 1=>"String8", 2=>0, 3=>1, 4=>0, 5=>"foo", 6=>"00", 7=>nil},
      {"addr"=>3, "opcode"=>"ResultRow", "p1"=>1, "p2"=>1, "p3"=>0, "p4"=>"", "p5"=>"00", "comment"=>nil, 0=>3, 1=>"ResultRow", 2=>1, 3=>1, 4=>0, 5=>"", 6=>"00", 7=>nil},
      {"addr"=>4, "opcode"=>"Halt", "p1"=>0, "p2"=>0, "p3"=>0, "p4"=>"", "p5"=>"00", "comment"=>nil, 0=>4, 1=>"Halt", 2=>0, 3=>0, 4=>0, 5=>"", 6=>"00", 7=>nil},
      {"addr"=>5, "opcode"=>"Goto", "p1"=>0, "p2"=>2, "p3"=>0, "p4"=>"", "p5"=>"00", "comment"=>nil, 0=>5, 1=>"Goto", 2=>0, 3=>2, 4=>0, 5=>"", 6=>"00", 7=>nil}
    ]
    connection.expects(:execute).with('EXPLAIN SELECT foo').returns(plan)
    NewRelic::Agent::Database.stubs(:get_connection).returns(connection)
    result = NewRelic::Agent::Database.explain_sql(sql, config, &@explainer)

    expected_headers = %w[addr opcode p1 p2 p3 p4 p5 comment]
    expected_values  = plan.map do |row|
      expected_headers.map { |h| row[h] }
    end

    assert_equal(expected_headers.sort, result[0].sort)
    assert_equal(expected_values, result[1])
  end

  def test_dont_collect_explain_for_parameterized_query
    config = {:adapter => 'postgresql'}
    config.default('val')
    connection = mock('param connection')
    connection.expects(:execute).never
    NewRelic::Agent::Database.stubs(:get_connection).with(config).returns(connection)
    expects_logging(:debug, 'Unable to collect explain plan for parameterized query.')

    sql = 'SELECT * FROM table WHERE id = $1'
    assert_equal [], NewRelic::Agent::Database.explain_sql(sql, config)
  end

  def test_do_collect_explain_for_parameter_looking_literal
    config = {:adapter => 'postgresql'}
    config.default('val')
    connection = mock('literal connection')
    plan = [{"QUERY PLAN"=>"Some Jazz"}]
    connection.stubs(:execute).returns(plan)
    NewRelic::Agent::Database.stubs(:get_connection).with(config).returns(connection)

    sql = "SELECT * FROM table WHERE id = 'noise $11'"
    assert_equal([['QUERY PLAN'], [["Some Jazz"]]],
                 NewRelic::Agent::Database.explain_sql(sql, config, &@explainer))
  end

  def test_dont_collect_explain_for_truncated_query
    config = {:adapter => 'postgresql'}
    config.default('val')
    connection = mock('truncated connection')
    connection.expects(:execute).never
    NewRelic::Agent::Database.stubs(:get_connection).with(config).returns(connection)
    expects_logging(:debug, 'Unable to collect explain plan for truncated query.')

    sql = 'SELECT * FROM table WHERE id IN (1,2,3,4,5...'
    assert_equal [], NewRelic::Agent::Database.explain_sql(sql, config)
  end

  def test_dont_collect_explain_if_adapter_not_recognized
    config = {:adapter => 'dorkdb'}
    config.default('val')
    connection = mock('connection')
    connection.expects(:execute).never
    NewRelic::Agent::Database.stubs(:get_connection).with(config).returns(connection)
    expects_logging(:debug, "Not collecting explain plan because an unknown connection adapter ('dorkdb') was used.")

    sql = 'SELECT * FROM table WHERE id IN (1,2,3,4,5)'
    assert_equal [], NewRelic::Agent::Database.explain_sql(sql, config)
  end

  def test_explain_sql_no_sql
    assert_equal(nil, NewRelic::Agent::Database.explain_sql(nil, nil))
  end

  def test_explain_sql_no_connection_config
    assert_equal(nil, NewRelic::Agent::Database.explain_sql('select foo', nil))
  end

  def test_explain_sql_non_select
    assert_equal([], NewRelic::Agent::Database.explain_sql('foo',
                                                           mock('config')))
  end

  def test_explain_sql_one_select_no_connection
    # NB this test raises an error in the log, much as it might if a
    # user supplied a config that was not valid. This is generally
    # expected behavior - the get_connection method shouldn't allow
    # errors to percolate up.
    config = mock('config')
    config.stubs(:[]).returns(nil)
    assert_equal([], NewRelic::Agent::Database.explain_sql('SELECT', config, &@explainer))
  end

  # See SqlObfuscationTest, which uses cross agent tests for the basic SQL
  # obfuscation test cases.

  def test_obfuscation_of_truncated_query
    insert = "INSERT INTO data (blah) VALUES ('abcdefg..."
    assert_equal("Query too large (over 16k characters) to safely obfuscate",
                 NewRelic::Agent::Database.obfuscate_sql(insert))
  end

  def test_sql_obfuscation_filters
    NewRelic::Agent::Database.set_sql_obfuscator(:replace) do |string|
      "1" + string
    end

    sql = "SELECT * FROM TABLE 123 'jim'"

    assert_equal "1" + sql, NewRelic::Agent::Database.obfuscate_sql(sql)

    NewRelic::Agent::Database.set_sql_obfuscator(:before) do |string|
      "2" + string
    end

    assert_equal "12" + sql, NewRelic::Agent::Database.obfuscate_sql(sql)

    NewRelic::Agent::Database.set_sql_obfuscator(:after) do |string|
      string + "3"
    end

    assert_equal "12" + sql + "3", NewRelic::Agent::Database.obfuscate_sql(sql)

    NewRelic::Agent::Database::Obfuscator.instance.reset
  end

  def test_close_connections_closes_all_held_db_connections
    foo_connection = mock('foo connection')
    bar_connection = mock('bar connection')
    NewRelic::Agent::Database::ConnectionManager.instance.instance_eval do
      @connections = { :foo => foo_connection, :bar => bar_connection }
    end
    foo_connection.expects(:disconnect!)
    bar_connection.expects(:disconnect!)

    NewRelic::Agent::Database.close_connections
  end

  def test_manager_get_connection_does_not_log_configuration_details_on_error
    config = "VOLDEMORT"
    connector = Proc.new { raise }
    error_log = with_array_logger(:error) do
      NewRelic::Agent::Database::ConnectionManager.instance.get_connection(config, &connector)
    end

    assert_equal false, error_log.array.join.include?('VOLDEMORT')
  end

  def test_default_sql_obfuscator_obfuscates_double_quoted_literals_with_unknown_adapter
    expected = "SELECT * FROM ? WHERE ? = ?"
    result = NewRelic::Agent::Database.obfuscate_sql("SELECT * FROM \"table\" WHERE \"col\" = 'value'")
    assert_equal expected, result
  end

  def test_capture_query_short_query
    query = 'a query'
    assert_equal(query, NewRelic::Agent::Database.capture_query(query))
  end

  def test_capture_query_long_query
    query = 'a' * NewRelic::Agent::Database::MAX_QUERY_LENGTH
    truncated_query = NewRelic::Agent::Database.capture_query(query)
    assert_equal('a' * (NewRelic::Agent::Database::MAX_QUERY_LENGTH - 3) + '...', truncated_query)
  end

  INVALID_UTF8_STRING = (''.respond_to?(:force_encoding) ? "\x80".force_encoding('UTF-8') : "\x80")

  def test_capture_query_mis_encoded
    query = INVALID_UTF8_STRING
    original_encoding = encoding_from_string(query)
    expected_query = INVALID_UTF8_STRING.dup
    expected_query.force_encoding('ASCII-8BIT') if expected_query.respond_to?(:force_encoding)
    captured = NewRelic::Agent::Database.capture_query(query)
    assert_equal(original_encoding, encoding_from_string(query)) # input query encoding should remain untouched
    assert_equal(expected_query, captured)
  end

  sql_parsing_tests = load_cross_agent_test('sql_parsing')
  sql_parsing_tests.each_with_index do |test_case, i|
    define_method("test_sql_parsing_#{i}") do
      result = NewRelic::Agent::Database.parse_operation_from_query(test_case['input'])
      assert_equal(test_case['operation'], result)
    end
  end

  # Ruby 1.8 doesn't have String#encoding
  def encoding_from_string(str)
    if str.respond_to?(:encoding)
      str.encoding
    else
      nil
    end
  end
end
