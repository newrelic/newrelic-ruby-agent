# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..',
                                   'test_helper'))
require 'new_relic/agent/database'
class NewRelic::Agent::DatabaseTest < Minitest::Test
  def teardown
    NewRelic::Agent::Database::Obfuscator.instance.reset
  end

  def test_adapter_from_config_string
    config = { :adapter => 'mysql' }
    statement = NewRelic::Agent::Database::Statement.new('some query', config)
    assert_equal(:mysql, statement.adapter)
  end

  def test_adapter_from_config_symbol
    config = { :adapter => :mysql }
    statement = NewRelic::Agent::Database::Statement.new('some query', config)
    assert_equal(:mysql, statement.adapter)
  end

  def test_adapter_from_config_uri_jdbc_postgresql
    config = { :uri=>"jdbc:postgresql://host/database?user=posgres" }
    statement = NewRelic::Agent::Database::Statement.new('some query', config)
    assert_equal(:postgres, statement.adapter)
  end

  def test_adapter_from_config_uri_jdbc_mysql
    config = { :uri=>"jdbc:mysql://host/database" }
    statement = NewRelic::Agent::Database::Statement.new('some query', config)
    assert_equal(:mysql, statement.adapter)
  end

  def test_adapter_from_config_uri_jdbc_sqlite
    config = { :uri => "jdbc:sqlite::memory" }
    statement = NewRelic::Agent::Database::Statement.new('some query', config)
    assert_equal(:sqlite, statement.adapter)
  end

  # An ActiveRecord::Result is what you get back when executing a
  # query using exec_query on the connection, which is what we're
  # doing now for explain plans in AR4 instrumentation
  def test_explain_sql_with_mysql2_activerecord_result
    return unless defined?(::ActiveRecord::Result)
    config = {:adapter => 'mysql2'}
    sql = 'SELECT * FROM spells where id=1'

    columns = ["id", "select_type", "table", "type", "possible_keys", "key", "key_len", "ref", "rows", "Extra"]
    rows = [["1", "SIMPLE", "spells", "const", "PRIMARY", "PRIMARY", "4", "const", "1", ""]]
    activerecord_result = ::ActiveRecord::Result.new(columns, rows)
    explainer = lambda { |statement| activerecord_result}

    statement = NewRelic::Agent::Database::Statement.new(sql, config, explainer)
    result = NewRelic::Agent::Database.explain_sql(statement)

    assert_equal([columns, rows], result)
  end

  def test_explain_sql_obfuscates_for_postgres_activerecord_result
    return unless defined?(::ActiveRecord::Result)
    config = {:adapter => 'postgres'}
    sql = "SELECT * FROM blogs WHERE blogs.id=1234 AND blogs.title='sensitive text'"

    columns = ["stuffs"]
    rows = [[" Index Scan using blogs_pkey on blogs  (cost=0.00..8.27 rows=1 width=540)"],
            ["   Index Cond: (id = 1234)"],
            ["   Filter: ((title)::text = 'sensitive text'::text)"]]
    activerecord_result = ::ActiveRecord::Result.new(columns, rows)
    explainer = lambda { |statement| activerecord_result}

    statement = NewRelic::Agent::Database::Statement.new(sql, config, explainer)
    expected_result = [['QUERY PLAN'],
                       [[" Index Scan using blogs_pkey on blogs  (cost=0.00..8.27 rows=1 width=540)"],
                        ["   Index Cond: ?"],
                        ["   Filter: ?"]
                      ]]

    with_config(:'transaction_tracer.record_sql' => 'obfuscated') do
      result = NewRelic::Agent::Database.explain_sql(statement)
      assert_equal(expected_result, result)
    end
  end

  # The following tests in the format _with_##_explain_result go
  # through the different kinds of results when using an explainer
  # that calls .execute on the connection

  def test_explain_sql_select_with_mysql_explain_result
    config = {:adapter => 'mysql'}
    sql = 'SELECT foo'

    plan = {
      "select_type"=>"SIMPLE", "key_len"=>nil, "table"=>"blogs", "id"=>"1",
      "possible_keys"=>nil, "type"=>"ALL", "Extra"=>"", "rows"=>"2",
      "ref"=>nil, "key"=>nil
    }
    explainer_result = mock('explain plan')
    explainer_result.expects(:each_hash).yields(plan)
    explainer = lambda { |statement| explainer_result}

    statement = NewRelic::Agent::Database::Statement.new(sql, config, explainer)
    result = NewRelic::Agent::Database.explain_sql(statement)
    expected_result = [["select_type", "key_len", "table", "id", "possible_keys", "type",
                        "Extra", "rows", "ref", "key"],
                       [["SIMPLE", nil, "blogs", "1", nil, "ALL", "", "2", nil, nil]]]

    assert_equal(expected_result[0].sort, result[0].sort, "Headers don't match")
    assert_equal(expected_result[1][0].compact.sort, result[1][0].compact.sort, "Values don't match")
  end

  def test_explain_sql_select_with_sequel
    config = { :adapter => 'mysql2' }
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
    explainer = lambda { |statement| plan_string}

    statement = NewRelic::Agent::Database::Statement.new(sql, config, explainer)
    result = NewRelic::Agent::Database.explain_sql(statement)

    assert_nil(result[0])
    assert_equal([plan_string], result[1])
  end

  def test_explain_sql_select_with_mysql2_explain_result
    config = {:adapter => 'mysql2'}
    sql = 'SELECT foo'

    plan_fields = ["select_type", "key_len", "table", "id", "possible_keys", "type", "Extra", "rows", "ref", "key"]
    plan_row =    ["SIMPLE",       nil,      "blogs", "1",   nil,            "ALL",  "",      "2",     nil,   nil ]
    explainer_result = mock('explain plan')
    explainer_result.expects(:fields).returns(plan_fields)
    explainer_result.expects(:each).yields(plan_row)
    explainer = lambda { |statement| explainer_result}

    statement = NewRelic::Agent::Database::Statement.new(sql, config, explainer)
    result = NewRelic::Agent::Database.explain_sql(statement)
    expected_result = [["select_type", "key_len", "table", "id", "possible_keys", "type",
                        "Extra", "rows", "ref","key"],
                       [["SIMPLE", nil, "blogs", "1", nil, "ALL", "", "2", nil, nil]]]

    assert_equal(expected_result[0].sort, result[0].sort, "Headers don't match")
    assert_equal(expected_result[1][0].compact.sort, result[1][0].compact.sort, "Values don't match")
  end

  def test_explain_sql_one_select_with_pg_explain_result
    config = {:adapter => 'postgresql'}
    sql = 'select count(id) from blogs limit 1'

    plan = [{"QUERY PLAN"=>"Limit  (cost=11.75..11.76 rows=1 width=4)"},
            {"QUERY PLAN"=>"  ->  Aggregate  (cost=11.75..11.76 rows=1 width=4)"},
            {"QUERY PLAN"=>"        ->  Seq Scan on blogs  (cost=0.00..11.40 rows=140 width=4)"}]
    explainer = lambda { |statement| plan}

    statement = NewRelic::Agent::Database::Statement.new(sql, config, explainer)
    result = NewRelic::Agent::Database.explain_sql(statement)
    expected_result = [['QUERY PLAN'],
                       [["Limit  (cost=11.75..11.76 rows=1 width=4)"],
                        ["  ->  Aggregate  (cost=11.75..11.76 rows=1 width=4)"],
                        ["        ->  Seq Scan on blogs  (cost=0.00..11.40 rows=140 width=4)"]
                       ]]

    assert_equal expected_result, result
  end

  def test_explain_sql_one_select_with_pg_explain_string_result
    config = {:adapter => 'postgresql'}
    sql = 'select count(id) from blogs limit 1'

    plan = "Limit  (cost=11.75..11.76 rows=1 width=4)
  ->  Aggregate  (cost=11.75..11.76 rows=1 width=4)
        ->  Seq Scan on blogs  (cost=0.00..11.40 rows=140 width=4)"
    explainer = lambda { |statement| plan}

    statement = NewRelic::Agent::Database::Statement.new(sql, config, explainer)
    result = NewRelic::Agent::Database.explain_sql(statement)
    expected_result = [['QUERY PLAN'],
                       [["Limit  (cost=11.75..11.76 rows=1 width=4)"],
                        ["  ->  Aggregate  (cost=11.75..11.76 rows=1 width=4)"],
                        ["        ->  Seq Scan on blogs  (cost=0.00..11.40 rows=140 width=4)"]
                       ]]

    assert_equal expected_result, result
  end

  def test_explain_sql_obfuscates_for_postgres
    config = {:adapter => 'postgresql'}
    sql = "SELECT * FROM blogs WHERE blogs.id=1234 AND blogs.title='sensitive text'"

    plan = [{"QUERY PLAN"=>" Index Scan using blogs_pkey on blogs  (cost=0.00..8.27 rows=1 width=540)"},
            {"QUERY PLAN"=>"   Index Cond: (id = 1234)"},
            {"QUERY PLAN"=>"   Filter: ((title)::text = 'sensitive text'::text)"}]
    explainer = lambda { |statement| plan}

    statement = NewRelic::Agent::Database::Statement.new(sql, config, explainer)
    expected_result = [['QUERY PLAN'],
                       [[" Index Scan using blogs_pkey on blogs  (cost=0.00..8.27 rows=1 width=540)"],
                        ["   Index Cond: ?"],
                        ["   Filter: ?"]
                      ]]

    with_config(:'transaction_tracer.record_sql' => 'obfuscated') do
      result = NewRelic::Agent::Database.explain_sql(statement)
      assert_equal expected_result, result
    end
  end

  def test_explain_sql_does_not_obfuscate_if_record_sql_raw
    config = {:adapter => 'postgresql'}
    sql = "SELECT * FROM blogs WHERE blogs.id=1234 AND blogs.title='sensitive text'"

    plan = [{"QUERY PLAN"=>" Index Scan using blogs_pkey on blogs  (cost=0.00..8.27 rows=1 width=540)"},
            {"QUERY PLAN"=>"   Index Cond: (id = 1234)"},
            {"QUERY PLAN"=>"   Filter: ((title)::text = 'sensitive text'::text)"}]
    explainer = lambda { |statement| plan}

    statement = NewRelic::Agent::Database::Statement.new(sql, config, explainer)
    expected_result = [['QUERY PLAN'],
                       [[" Index Scan using blogs_pkey on blogs  (cost=0.00..8.27 rows=1 width=540)"],
                        ["   Index Cond: (id = 1234)"],
                        ["   Filter: ((title)::text = 'sensitive text'::text)"]
                      ]]

    with_config(:'transaction_tracer.record_sql' => 'raw') do
      result = NewRelic::Agent::Database.explain_sql(statement)
      assert_equal expected_result, result
    end
  end

  def test_explain_sql_select_with_sqlite_explain_string_result
    config = {:adapter => 'sqlite'}
    sql = 'SELECT foo'

    plan = [
      {"addr"=>0, "opcode"=>"Trace", "p1"=>0, "p2"=>0, "p3"=>0, "p4"=>"", "p5"=>"00", "comment"=>nil, 0=>0, 1=>"Trace", 2=>0, 3=>0, 4=>0, 5=>"", 6=>"00", 7=>nil},
      {"addr"=>1, "opcode"=>"Goto",  "p1"=>0, "p2"=>5, "p3"=>0, "p4"=>"", "p5"=>"00", "comment"=>nil, 0=>1, 1=>"Goto",  2=>0, 3=>5, 4=>0, 5=>"", 6=>"00", 7=>nil},
      {"addr"=>2, "opcode"=>"String8", "p1"=>0, "p2"=>1, "p3"=>0, "p4"=>"foo", "p5"=>"00", "comment"=>nil, 0=>2, 1=>"String8", 2=>0, 3=>1, 4=>0, 5=>"foo", 6=>"00", 7=>nil},
      {"addr"=>3, "opcode"=>"ResultRow", "p1"=>1, "p2"=>1, "p3"=>0, "p4"=>"", "p5"=>"00", "comment"=>nil, 0=>3, 1=>"ResultRow", 2=>1, 3=>1, 4=>0, 5=>"", 6=>"00", 7=>nil},
      {"addr"=>4, "opcode"=>"Halt", "p1"=>0, "p2"=>0, "p3"=>0, "p4"=>"", "p5"=>"00", "comment"=>nil, 0=>4, 1=>"Halt", 2=>0, 3=>0, 4=>0, 5=>"", 6=>"00", 7=>nil},
      {"addr"=>5, "opcode"=>"Goto", "p1"=>0, "p2"=>2, "p3"=>0, "p4"=>"", "p5"=>"00", "comment"=>nil, 0=>5, 1=>"Goto", 2=>0, 3=>2, 4=>0, 5=>"", 6=>"00", 7=>nil}
    ]
    explainer = lambda { |statement| plan}

    statement = NewRelic::Agent::Database::Statement.new(sql, config, explainer)
    result = NewRelic::Agent::Database.explain_sql(statement)

    expected_headers = %w[addr opcode p1 p2 p3 p4 p5 comment]
    expected_values  = plan.map do |row|
      expected_headers.map { |h| row[h] }
    end

    assert_equal(expected_headers.sort, result[0].sort)
    assert_equal(expected_values, result[1])
  end

  def test_explain_sql_select_with_sqlite3_explain_string_result
    config = {:adapter => 'sqlite3'}
    sql = 'SELECT foo'

    plan = [
      {"addr"=>0, "opcode"=>"Trace", "p1"=>0, "p2"=>0, "p3"=>0, "p4"=>"", "p5"=>"00", "comment"=>nil, 0=>0, 1=>"Trace", 2=>0, 3=>0, 4=>0, 5=>"", 6=>"00", 7=>nil},
      {"addr"=>1, "opcode"=>"Goto",  "p1"=>0, "p2"=>5, "p3"=>0, "p4"=>"", "p5"=>"00", "comment"=>nil, 0=>1, 1=>"Goto",  2=>0, 3=>5, 4=>0, 5=>"", 6=>"00", 7=>nil},
      {"addr"=>2, "opcode"=>"String8", "p1"=>0, "p2"=>1, "p3"=>0, "p4"=>"foo", "p5"=>"00", "comment"=>nil, 0=>2, 1=>"String8", 2=>0, 3=>1, 4=>0, 5=>"foo", 6=>"00", 7=>nil},
      {"addr"=>3, "opcode"=>"ResultRow", "p1"=>1, "p2"=>1, "p3"=>0, "p4"=>"", "p5"=>"00", "comment"=>nil, 0=>3, 1=>"ResultRow", 2=>1, 3=>1, 4=>0, 5=>"", 6=>"00", 7=>nil},
      {"addr"=>4, "opcode"=>"Halt", "p1"=>0, "p2"=>0, "p3"=>0, "p4"=>"", "p5"=>"00", "comment"=>nil, 0=>4, 1=>"Halt", 2=>0, 3=>0, 4=>0, 5=>"", 6=>"00", 7=>nil},
      {"addr"=>5, "opcode"=>"Goto", "p1"=>0, "p2"=>2, "p3"=>0, "p4"=>"", "p5"=>"00", "comment"=>nil, 0=>5, 1=>"Goto", 2=>0, 3=>2, 4=>0, 5=>"", 6=>"00", 7=>nil}
    ]
    explainer = lambda { |statement| plan}

    statement = NewRelic::Agent::Database::Statement.new(sql, config, explainer)
    result = NewRelic::Agent::Database.explain_sql(statement)

    expected_headers = %w[addr opcode p1 p2 p3 p4 p5 comment]
    expected_values  = plan.map do |row|
      expected_headers.map { |h| row[h] }
    end

    assert_equal(expected_headers.sort, result[0].sort)
    assert_equal(expected_values, result[1])
  end

  def test_explain_sql_no_sql
    statement = NewRelic::Agent::Database::Statement.new('', nil)
    assert_equal(nil, NewRelic::Agent::Database.explain_sql(statement))
  end

  def test_explain_sql_non_select
    statement = NewRelic::Agent::Database::Statement.new('foo', mock('config'), mock('explainer'))
    assert_equal([], NewRelic::Agent::Database.explain_sql(statement))
  end

  def test_dont_collect_explain_for_truncated_query
    config = {:adapter => 'postgresql'}
    sql = 'SELECT * FROM table WHERE id IN (1,2,3,4,5...'
    statement = NewRelic::Agent::Database::Statement.new(sql, config, mock('explainer'))

    expects_logging(:debug, 'Unable to collect explain plan for truncated query.')
    assert_equal [], NewRelic::Agent::Database.explain_sql(statement)
  end

  def test_dont_collect_explain_for_parameterized_query
    config = {:adapter => 'postgresql'}
    sql = 'SELECT * FROM table WHERE id = $1'
    statement = NewRelic::Agent::Database::Statement.new(sql, config, mock('explainer'))

    expects_logging(:debug, 'Unable to collect explain plan for parameter-less parameterized query.')
    assert_equal [], NewRelic::Agent::Database.explain_sql(statement)
  end

  def test_do_collect_explain_for_parameter_looking_literal
    config = {:adapter => 'postgresql'}
    sql = "SELECT * FROM table WHERE id = 'noise $11'"
    plan = [{"QUERY PLAN"=>"Some Jazz"}]
    explainer = lambda { |statement| plan}
    statement = NewRelic::Agent::Database::Statement.new(sql, config, explainer)

    assert_equal([['QUERY PLAN'], [["Some Jazz"]]],
                 NewRelic::Agent::Database.explain_sql(statement))
  end

  def test_do_collect_explain_for_parameterized_query_with_binds
    config = {:adapter => 'postgresql'}
    sql = 'SELECT * FROM table WHERE id = $1'
    # binds objects don't actually look like this, just need non-blank for test
    binds = "values for the parameters"
    plan = [{"QUERY PLAN"=>"Some Jazz"}]
    explainer = lambda { |statement| plan}
    statement = NewRelic::Agent::Database::Statement.new(sql, config, explainer, binds)

    assert_equal([['QUERY PLAN'], [["Some Jazz"]]],
                 NewRelic::Agent::Database.explain_sql(statement))
  end

  def test_dont_collect_explain_if_adapter_not_recognized
    config = {:adapter => 'dorkdb'}
    sql = 'SELECT * FROM table WHERE id IN (1,2,3,4,5)'
    statement = NewRelic::Agent::Database::Statement.new(sql, config, mock('explainer'))

    expects_logging(:debug, "Not collecting explain plan because an unknown connection adapter ('dorkdb') was used.")
    assert_equal [], NewRelic::Agent::Database.explain_sql(statement)
  end

  def test_explain_sql_no_connection_config
    statement = NewRelic::Agent::Database::Statement.new('select foo', nil)
    assert_equal(nil, NewRelic::Agent::Database.explain_sql(statement))
  end

  def test_explain_sql_one_select_no_connection
    # NB this test raises an error in the log, much as it might if a
    # user supplied a config that was not valid. This is generally
    # expected behavior - the get_connection method shouldn't allow
    # errors to percolate up.
    config = mock('config')
    config.stubs(:[]).returns(nil)

    # if you have an invalid config or no connection, the explainer returns nil
    explainer = lambda { |statement| nil}
    statement = NewRelic::Agent::Database::Statement.new('SELECT', config, explainer)

    assert_equal([], NewRelic::Agent::Database.explain_sql(statement))
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

  INVALID_UTF8_STRING = (''.respond_to?(:force_encoding) ? "select \x80".force_encoding('UTF-8') : "select \x80")

  def test_capture_query_mis_encoded
    query = INVALID_UTF8_STRING
    original_encoding = encoding_from_string(query)
    expected_query = INVALID_UTF8_STRING.dup
    expected_query.force_encoding('ASCII-8BIT') if expected_query.respond_to?(:force_encoding)
    captured = NewRelic::Agent::Database.capture_query(query)
    assert_equal(original_encoding, encoding_from_string(query)) # input query encoding should remain untouched
    assert_equal(expected_query, captured)
  end

  def test_parse_operation_from_query_mis_encoded
    query = INVALID_UTF8_STRING
    expected = "select"
    parsed = NewRelic::Agent::Database.parse_operation_from_query(query)
    assert_equal(expected, parsed)
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
