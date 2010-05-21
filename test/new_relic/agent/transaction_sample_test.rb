ENV['SKIP_RAILS'] = 'true'
require File.expand_path('../../../test_helper.rb', __FILE__) 

class NewRelic::TransactionSampleTest < Test::Unit::TestCase
  extend TestContexts
  include TransactionSampleTestHelper
  ::SQL_STATEMENT = "SELECT * from sandwiches"
  
  with_running_agent do
    
    context "a sql transaction" do
      setup do
        @connection_stub = Mocha::Mockery.instance.named_mock('connection')
        @connection_stub.stubs(:execute).returns('QUERY RESULT')
        
        NewRelic::TransactionSample.stubs(:get_connection).returns @connection_stub
        #        NewRelic::TransactionSample::Segment.any_instance.stubs(:explain_sql).returns([[["QUERY RESULT"]],[["QUERY RESULT"]]])
        #        NewRelic::TransactionSample::Segment.any_instance.expects(:handle_exception_in_explain).never
        @t = make_sql_transaction(::SQL_STATEMENT, ::SQL_STATEMENT)
      end
      
      should "be recorded" do
        assert_not_nil @t
      end
      
      should "not record sql when record_sql => off" do
        s = @t.prepare_to_send(:explain_sql => 0.00000001)
        s.each_segment do |segment|
          assert_nil segment.params[:explanation]
          assert_nil segment.params[:sql]
        end        
      end
      
      should "record raw sql" do
        s = @t.prepare_to_send(:explain_sql => 0.00000001, :record_sql => :raw)
        got_one = false
        s.each_segment do |segment|
          fail if segment.params[:obfuscated_sql]
          got_one = got_one || segment.params[:explanation] || segment.params[:sql]
        end
        assert got_one
      end
      
      should "record obfuscated sql" do
        
        s = @t.prepare_to_send(:explain_sql => 0.00000001, :record_sql => :obfuscated)
        
        got_one = false
        s.each_segment do |segment|
          got_one = got_one || segment.params[:explanation] || segment.params[:sql]
        end        
        
        assert got_one
      end
      
      should "have sql rows when sql is recorded" do
        s = @t.prepare_to_send(:explain_sql => 0.00000001)
        
        assert s.sql_segments.empty?
        s.root_segment[:sql] = 'hello'
        assert !s.sql_segments.empty?
      end
      
      should "have sql rows when sql is obfuscated" do
        s = @t.prepare_to_send(:explain_sql => 0.00000001)
        
        assert s.sql_segments.empty?
        s.root_segment[:sql_obfuscated] = 'hello'
        assert !s.sql_segments.empty?
      end
      
      should "have sql rows when recording non-sql keys" do
        s = @t.prepare_to_send(:explain_sql => 0.00000001)
        
        assert s.sql_segments.empty?
        s.root_segment[:key] = 'hello'
        assert !s.sql_segments.empty?
      end
      
      should "catch exceptions" do
        @connection_stub.expects(:execute).raises
        # the sql connection will throw
        @t.prepare_to_send(:record_sql => :obfuscated, :explain_sql => 0.00000001)
      end
      
      should "have explains" do
        
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
    end     
    
    
    should "not record sql without record_sql option" do
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
    
    context "in disabled transaction tracing block" do
      should "not record transactions" do
        NewRelic::Agent.disable_transaction_tracing do
          t = make_sql_transaction(::SQL_STATEMENT, ::SQL_STATEMENT)
          assert t.nil?
        end
      end
    end
    
    context "a nested sample" do
      
      setup do
        @t = NewRelic::TransactionSample.new
        
        @t.params[:test] = "hi"
        
        s1 = @t.create_segment(1.0, "controller")
        
        @t.root_segment.add_called_segment(s1)
        
        s2 = @t.create_segment(2.0, "AR1")
        
        s2.params[:test] = "test"
        
        s1.add_called_segment(s2)
        s2.end_trace 3.0
        s1.end_trace 4.0
        
        s3 = @t.create_segment(4.0, "post_filter")
        @t.root_segment.add_called_segment(s3)
        s3.end_trace 6.0
        
        s4 = @t.create_segment(6.0, "post_filter")
        @t.root_segment.add_called_segment(s4)
        s4.end_trace 7.0
      end
      
      should "exclusive_duration" do
        s1 = @t.root_segment.called_segments.first
        assert_equal 3.0, s1.duration
        assert_equal 2.0, s1.exclusive_duration
      end
      
      should "count the segments" do
        assert_equal 4, @t.count_segments
      end
      
      should "truncate long samples" do
        @t.truncate(2)
        assert_equal 2, @t.count_segments
        
        @t = NewRelic::TransactionSample.new
        
        s1 = @t.create_segment(1.0, "controller")
        @t.root_segment.add_called_segment(s1)
        
        100.times do
          s1.add_called_segment(@t.create_segment(1.0, "segment"))
        end
        assert_equal 101, @t.count_segments
        @t.truncate(2)
        assert_equal 2, @t.count_segments
        assert_equal 101, @t.params[:segment_count]
      end
      
    end
    
  end
  
  
end