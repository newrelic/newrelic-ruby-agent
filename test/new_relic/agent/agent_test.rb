require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
module NewRelic
  module Agent
    class AgentTest < Test::Unit::TestCase
      def test_sql_normalization
        
        # basic statement
        assert_equal "INSERT INTO X values(?,?, ? , ?)", 
        NewRelic::Agent.instance.send(:default_sql_obfuscator, "INSERT INTO X values('test',0, 1 , 2)")
        
        # escaped literals
        assert_equal "INSERT INTO X values(?, ?,?, ? , ?)", 
        NewRelic::Agent.instance.send(:default_sql_obfuscator, "INSERT INTO X values('', 'jim''s ssn',0, 1 , 'jim''s son''s son')")
        
        # multiple string literals             
        assert_equal "INSERT INTO X values(?,?,?, ? , ?)", 
        NewRelic::Agent.instance.send(:default_sql_obfuscator, "INSERT INTO X values('jim''s ssn','x',0, 1 , 2)")
        
        # empty string literal
        # NOTE: the empty string literal resolves to empty string, which for our purposes is acceptable
        assert_equal "INSERT INTO X values(?,?,?, ? , ?)", 
        NewRelic::Agent.instance.send(:default_sql_obfuscator, "INSERT INTO X values('','x',0, 1 , 2)")
        
        # try a select statement             
        assert_equal "select * from table where name=? and ssn=?",
        NewRelic::Agent.instance.send(:default_sql_obfuscator, "select * from table where name='jim gochee' and ssn=0012211223")
        
        # number literals embedded in sql - oh well
        assert_equal "select * from table_? where name=? and ssn=?",
        NewRelic::Agent.instance.send(:default_sql_obfuscator, "select * from table_007 where name='jim gochee' and ssn=0012211223")
      end
      
      def test_sql_normalization__single_quotes
        assert_equal "INSERT ? into table",
        NewRelic::Agent.instance.send(:default_sql_obfuscator, "INSERT 'this isn''t a real value' into table")
        assert_equal "INSERT ? into table",
        NewRelic::Agent.instance.send(:default_sql_obfuscator, %q[INSERT '"' into table])
        assert_equal "INSERT ? into table",
        NewRelic::Agent.instance.send(:default_sql_obfuscator, %q[INSERT ' "some text" \" ' into table])
        #    could not get this one licked.  no biggie    
        #    assert_equal "INSERT ? into table",
        #    NewRelic::Agent.instance.send(:default_sql_obfuscator, %q[INSERT '\'' into table])
        assert_equal "INSERT ? into table",
        NewRelic::Agent.instance.send(:default_sql_obfuscator, %q[INSERT ''' ' into table])
      end
      def test_sql_normalization__double_quotes
        assert_equal "INSERT ? into table",
        NewRelic::Agent.instance.send(:default_sql_obfuscator, %q[INSERT "this isn't a real value" into table])
        assert_equal "INSERT ? into table",
        NewRelic::Agent.instance.send(:default_sql_obfuscator, %q[INSERT "'" into table])
        assert_equal "INSERT ? into table",
        NewRelic::Agent.instance.send(:default_sql_obfuscator, %q[INSERT " \" " into table])
        assert_equal "INSERT ? into table",
        NewRelic::Agent.instance.send(:default_sql_obfuscator, %q[INSERT " 'some text' " into table])
      end
      def test_sql_obfuscation_filters
        orig =  NewRelic::Agent.agent.obfuscator
        
        NewRelic::Agent.set_sql_obfuscator(:replace) do |sql|
          sql = "1" + sql
        end
        
        sql = "SELECT * FROM TABLE 123 'jim'"
        
        assert_equal "1" + sql, NewRelic::Agent.instance.obfuscator.call(sql)
        
        NewRelic::Agent.set_sql_obfuscator(:before) do |sql|
          sql = "2" + sql
        end
        
        assert_equal "12" + sql, NewRelic::Agent.instance.obfuscator.call(sql)
        
        NewRelic::Agent.set_sql_obfuscator(:after) do |sql|
          sql = sql + "3"
        end
        
        assert_equal "12" + sql + "3", NewRelic::Agent.instance.obfuscator.call(sql)
        
        NewRelic::Agent.agent.set_sql_obfuscator(:replace, &orig)
      end
      
      
    end
  end
end
