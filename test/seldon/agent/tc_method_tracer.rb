require File.join(File.dirname(__FILE__),'mock_agent')
require 'seldon/agent/method_tracer'
require 'test/unit'

module Seldon
  module Agent
    
    # for testing, enable the stats engine to clear itself
    class StatsEngine
      def reset
        scope_stack.clear
        @stats_hash.clear
      end
    end
    
    extend self
    def module_method_to_be_traced (x, testcase)
      testcase.assert x == "x"
      testcase.assert testcase.stats_engine.peek_scope == "x"
    end
    
    class MethodTracerTests < Test::Unit::TestCase
      attr_reader :stats_engine
      
      def setup
        @stats_engine = Agent.instance.stats_engine
        @stats_engine.reset
      end
      
      def teardown
        self.class.remove_tracer_from_method :method_to_be_traced, @metric_name if @metric_name
        @metric_name = nil
      end
      
      def test_basic
        metric = "hello"
        t1 = Time.now
        self.class.trace_method_execution metric do
          sleep 0.1
          assert metric == @stats_engine.peek_scope
        end
        elapsed = Time.now - t1
        
        stats = @stats_engine.get_stats(metric)
        check_time stats.total_call_time, elapsed
        assert stats.call_count == 1
      end
      
      METRIC = "metric"
      def test_add_method_tracer
        @metric_name = METRIC
        self.class.add_tracer_to_method :method_to_be_traced, METRIC
        
        t1 = Time.now
        method_to_be_traced 1,2,3,true,METRIC
        elapsed = Time.now - t1
        
        stats = @stats_engine.get_stats(METRIC)
        check_time stats.total_call_time, elapsed
        assert stats.call_count == 1
      end
      
      def test_add_tracer_with_dynamic_metric
        metric_code = '#{args[0]}.#{args[1]}'
        @metric_name = metric_code
        expected_metric = "1.2"
        self.class.add_tracer_to_method :method_to_be_traced, metric_code
        
        t1 = Time.now
        method_to_be_traced 1,2,3,true,expected_metric
        elapsed = Time.now - t1
        
        stats = @stats_engine.get_stats(expected_metric)
        check_time stats.total_call_time, elapsed
        assert stats.call_count == 1
      end
      
      def method_to_be_traced(x, y, z, is_traced, expected_metric)
        sleep 0.1
        assert x == 1
        assert y == 2
        assert z == 3
        assert((expected_metric == @stats_engine.peek_scope) == is_traced)
      end
      
      def test_trace_module_method
        Seldon::Agent.add_tracer_to_method :module_method_to_be_traced, '#{args[0]}'
        Seldon::Agent.module_method_to_be_traced "x", self
        Seldon::Agent.remove_tracer_from_method :module_method_to_be_traced, '#{args[0]}'
      end
      
      def test_remove
        self.class.add_tracer_to_method :method_to_be_traced, METRIC
        self.class.remove_tracer_from_method :method_to_be_traced, METRIC
          
        t1 = Time.now
        method_to_be_traced 1,2,3,false,METRIC
        elapsed = Time.now - t1
        
        stats = @stats_engine.get_stats(METRIC)
        assert stats.call_count == 0
      end
      
      def MethodTracerTests.static_method(x, testcase, is_traced)
        testcase.assert x == "x"
        testcase.assert((testcase.stats_engine.peek_scope == "x") == is_traced)
      end

      def trace_trace_static_method
        self.add_tracer_to_method :static_method, '#{args[0]}'
        self.class.static_method "x", self, true
        self.remove_tracer_from_method :static_method, '#{args[0]}'
        self.class.static_method "x", self, false
      end
        
      def test_execption
        begin
          metric = "hey there"
          self.class.trace_method_execution metric do
            assert @stats_engine.peek_scope == metric
            throw Exception.new            
          end
          
          assert false # should never get here
        rescue Exception
          # make sure the scope gets popped
          assert @stats_engine.peek_scope == nil
        end
        
        stats = @stats_engine.get_stats metric
        assert stats.call_count == 1
      end
      
      def check_time (t1, t2)
        assert((t2-t1).abs < 0.01)
      end
    end
  end
end

