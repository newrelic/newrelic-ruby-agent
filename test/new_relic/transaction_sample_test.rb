require File.expand_path('../../test_helper.rb', __FILE__) 

class NewRelic::TransactionSampleTest < Test::Unit::TestCase
  include TransactionSampleTestHelper
  ::SQL_STATEMENT = "SELECT * from sandwiches"

  def setup
    @connection_stub = Mocha::Mockery.instance.named_mock('connection')
    @connection_stub.stubs(:execute).returns('QUERY RESULT')
    
    NewRelic::TransactionSample.stubs(:get_connection).returns @connection_stub
    @t = make_sql_transaction(::SQL_STATEMENT, ::SQL_STATEMENT)
  end
  
  def test_be_recorded
    assert_not_nil @t
  end
  
  def test_not_record_sql_when_record_sql_off
    s = @t.prepare_to_send(:explain_sql => 0.00000001)
    s.each_segment do |segment|
      assert_nil segment.params[:explanation]
      assert_nil segment.params[:sql]
    end        
  end
  
  def test_record_raw_sql
    s = @t.prepare_to_send(:explain_sql => 0.00000001, :record_sql => :raw)
    got_one = false
    s.each_segment do |segment|
      fail if segment.params[:obfuscated_sql]
      got_one = got_one || segment.params[:explanation] || segment.params[:sql]
    end
    assert got_one
  end
  
  def test_record_obfuscated_sql
    
    s = @t.prepare_to_send(:explain_sql => 0.00000001, :record_sql => :obfuscated)

    got_one = false
    s.each_segment do |segment|
      got_one = got_one || segment.params[:explanation] || segment.params[:sql]
    end        
    
    assert got_one
  end
  
  def test_have_sql_rows_when_sql_is_recorded
    s = @t.prepare_to_send(:explain_sql => 0.00000001)
    
    assert s.sql_segments.empty?
    s.root_segment[:sql] = 'hello'
    assert !s.sql_segments.empty?
  end
  
  def test_have_sql_rows_when_sql_is_obfuscated
    s = @t.prepare_to_send(:explain_sql => 0.00000001)
    
    assert s.sql_segments.empty?
    s.root_segment[:sql_obfuscated] = 'hello'
    assert !s.sql_segments.empty?
  end
  
  def test_have_sql_rows_when_recording_non_sql_keys
    s = @t.prepare_to_send(:explain_sql => 0.00000001)
    
    assert s.sql_segments.empty?
    s.root_segment[:key] = 'hello'
    assert !s.sql_segments.empty?
  end
  
  def test_catch_exceptions
    @connection_stub.expects(:execute).raises
    # the sql connection will throw
    @t.prepare_to_send(:record_sql => :obfuscated, :explain_sql => 0.00000001)
  end
  
  def test_have_explains
    
    s = @t.prepare_to_send(:record_sql => :obfuscated, :explain_sql => 0.00000001)
    
    explain_count = 0
    s.each_segment do |segment|
      if segment.params[:explanation]
        explanations = segment.params[:explanation]
        
        explanations.each do |explanation|
          assert_kind_of Array, explanation
          assert_kind_of Array, explanation[0]
          assert_equal "QUERY RESULT", explanation[0][0]
          explain_count += 1
        end
      end
    end
    assert_equal 2, explain_count
  end

  def test_not_record_sql_without_record_sql_option
    t = nil
    NewRelic::Agent.disable_sql_recording do
      t = make_sql_transaction(::SQL_STATEMENT, ::SQL_STATEMENT)
    end
    
    s = t.prepare_to_send(:explain_sql => 0.00000001)
    
    s.each_segment do |segment|
      assert_nil segment.params[:explanation]
      assert_nil segment.params[:sql]
    end
  end        

  def test_not_record_transactions
    NewRelic::Agent.disable_transaction_tracing do
      t = make_sql_transaction(::SQL_STATEMENT, ::SQL_STATEMENT)
      assert t.nil?
    end
  end
  
end
