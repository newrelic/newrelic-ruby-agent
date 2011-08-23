require File.expand_path(File.join(File.dirname(__FILE__), '..', '..',
                                   'test_helper'))
require 'new_relic/agent/database'
class NewRelic::Agent::DatabaseTest < Test::Unit::TestCase
  def test_process_resultset
    resultset = [["column"]]
    assert_equal([nil, [["column"]]],
                 NewRelic::Agent::Database.process_resultset(resultset))
  end
  
  def test_explain_sql_select_with_mysql_connection
    config = {:adapter => 'mysql'}
    config.default('val')
    sql = 'SELECT foo'
    connection = mock('connection')
    plan = {
      "select_type"=>"SIMPLE", "key_len"=>nil, "table"=>"blogs", "id"=>"1",
      "possible_keys"=>nil, "type"=>"ALL", "Extra"=>"", "rows"=>"2",
      "ref"=>nil, "key"=>nil
    }
    result = mock('explain plan')
    result.expects(:each_hash).yields(plan)
    # two rows, two columns
    connection.expects(:execute).with('EXPLAIN SELECT foo').returns(result)
    NewRelic::Agent::Database.expects(:get_connection).with(config).returns(connection)

    result = NewRelic::Agent::Database.explain_sql(sql, config)
    assert_equal(plan.keys.sort, result[0].sort)
    assert_equal(plan.values.compact.sort, result[1][0].compact.sort)    
  end

  def test_explain_sql_one_select_with_pg_connection
    config = {:adapter => 'postgresql'}
    config.default('val')
    sql = 'select count(id) from blogs limit 1'
    connection = mock('connection')
    plan = [{"QUERY PLAN"=>"Limit  (cost=11.75..11.76 rows=1 width=4)"},
            {"QUERY PLAN"=>"  ->  Aggregate  (cost=11.75..11.76 rows=1 width=4)"},
            {"QUERY PLAN"=>"        ->  Seq Scan on blogs  (cost=0.00..11.40 rows=140 width=4)"}]
    connection.expects(:execute).returns(plan)
    NewRelic::Agent::Database.expects(:get_connection).with(config).returns(connection)
    assert_equal([['QUERY PLAN'],
                  [["Limit  (cost=11.75..11.76 rows=1 width=4)"],
                   ["  ->  Aggregate  (cost=11.75..11.76 rows=1 width=4)"],
                   ["        ->  Seq Scan on blogs  (cost=0.00..11.40 rows=140 width=4)"]]],
                 NewRelic::Agent::Database.explain_sql(sql, config))
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
    assert_equal([], NewRelic::Agent::Database.explain_sql('SELECT', config))
  end  
  
  def test_handle_exception_in_explain
    fake_error = Exception.new('a message')
    NewRelic::Control.instance.log.expects(:error).with('Error getting query plan: a message')
    # backtrace can be basically any string, just should get logged
    NewRelic::Control.instance.log.expects(:debug).with(instance_of(String))
    
    NewRelic::Agent::Database.handle_exception_in_explain do
      raise(fake_error)
    end
  end
end
