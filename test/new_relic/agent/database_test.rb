# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..',
                                   'test_helper'))
require 'new_relic/agent/database'
class NewRelic::Agent::DatabaseTest < Test::Unit::TestCase
  def setup
    @explainer = NewRelic::Agent::Instrumentation::ActiveRecord::EXPLAINER
  end

  def teardown
    NewRelic::Agent::Database::Obfuscator.instance.reset
  end

  def test_process_resultset
    resultset = [["column"]]
    assert_equal([nil, [["column"]]],
                 NewRelic::Agent::Database.process_resultset(resultset))
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

  def test_obfuscation_mysql_basic
    insert = %q[INSERT INTO `X` values("test",0, 1 , 2, 'test')]
    assert_equal("INSERT INTO `X` values(?,?, ? , ?, ?)",
                 NewRelic::Agent::Database.obfuscate_sql(insert))
    select = %q[SELECT `table`.`column` FROM `table` WHERE `table`.`column` = 'value' AND `table`.`other_column` = "other value" LIMIT 1]
    assert_equal(%q[SELECT `table`.`column` FROM `table` WHERE `table`.`column` = ? AND `table`.`other_column` = ? LIMIT ?],
                 NewRelic::Agent::Database.obfuscate_sql(select))
  end

  def test_obfuscation_postgresql_basic
    insert = NewRelic::Agent::Database::Statement.new(%q[INSERT INTO "X" values('test',0, 1 , 2, 'test')])
    insert.adapter = :postgresql
    assert_equal('INSERT INTO "X" values(?,?, ? , ?, ?)',
                 NewRelic::Agent::Database.obfuscate_sql(insert))
    select = NewRelic::Agent::Database::Statement.new(%q[SELECT "table"."column" FROM "table" WHERE "table"."column" = 'value' AND "table"."other_column" = 'other value' LIMIT 1])
    select.adapter = :postgresql
    assert_equal(%q[SELECT "table"."column" FROM "table" WHERE "table"."column" = ? AND "table"."other_column" = ? LIMIT ?],
                 NewRelic::Agent::Database.obfuscate_sql(select))
  end

  def test_obfuscation_escaped_literals
    insert = %q[INSERT INTO X values('', 'jim''s ssn',0, 1 , 'jim''s son''s son', """jim''s"" hat", "\"jim''s secret\"")]
    assert_equal("INSERT INTO X values(?, ?,?, ? , ?, ?, ?)",
                 NewRelic::Agent::Database.obfuscate_sql(insert))
  end

  def test_obfuscation_mysql_integers_in_identifiers
    select = %q[SELECT * FROM `table_007` LIMIT 1]
    assert_equal(%q[SELECT * FROM `table_007` LIMIT ?],
                 NewRelic::Agent::Database.obfuscate_sql(select))
  end

  def test_obfuscation_postgresql_integers_in_identifiers
    select = NewRelic::Agent::Database::Statement.new(%q[SELECT * FROM "table_007" LIMIT 1])
    select.adapter = :postgresql
    assert_equal(%q[SELECT * FROM "table_007" LIMIT ?],
                 NewRelic::Agent::Database.obfuscate_sql(select))
  end

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
end
