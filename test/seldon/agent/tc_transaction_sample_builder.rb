require 'newrelic/agent/transaction_sampler'
require 'test/unit'

module NewRelic 
  module Agent
    class TransationSampleBuilderTests < Test::Unit::TestCase

      def setup
        @builder = TransactionSampleBuilder.new
      end
    
      def test_build_sample
        build_segment("a") do
          build_segment("aa") do
            build_segment("aaa")
          end
          build_segment("ab") do
            build_segment("aba") do
              build_segment("abaa")
            end
            build_segment("aba")
            build_segment("abc") do
              build_segment("abca")
              build_segment("abcd")
            end
          end
        end
        build_segment "b"
        build_segment "c" do
          build_segment "ca" 
          build_segment "cb" do
            build_segment "cba"
          end
        end
      
        @builder.finish_trace
        validate_builder
      end
    
      def test_freeze
        build_segment "a" do
          build_segment "aa"
        end
        
        begin 
          builder.sample
          assert false
        rescue Exception => e
          # expected
        end
        
        @builder.finish_trace
      
        validate_builder
      
        begin
          build_segment "b"
          assert_false
        rescue TypeError => e
          # expected
        end
      end
      
      def test_marshal
        build_segment "a" do
          build_segment "ab"
        end
        build_segment "b" do
          build_segment "ba"
          build_segment "bb"
          build_segment "bc" do
            build_segment "bca"
          end
        end
        build_segment "c"
        
        @builder.finish_trace
        validate_builder
        
        dump = Marshal.dump @builder.sample
        sample = Marshal.restore(dump)
        validate_segment(sample.root_segment)
      end
        
      
      def validate_builder
        validate_segment @builder.sample.root_segment
      end
    
      def validate_segment(s)
        parent = s.parent_segment

        unless p.nil?
          assert p.called_segments.include?(s) 
          assert p.metric_name.length == s.metric_name.length - 1
          assert p.metric_name < s.metric_name
          assert p.entry_timestamp <= s.entry_timestamp
        end
      
        assert s.exit_timestamp >= s.entry_timestamp
      
        children = s.called_segments
        last_segment = s
        children.each do |child|
          assert child.metric_name > last_segment.metric_name
          assert child.entry_timestamp >= last_segment.entry_timestamp
          last_metric = child
        
          validate_segment(child)
        end
      end
      
      def build_segment(metric, &proc)
        @builder.trace_entry(metric)
        proc.call if proc
        @builder.trace_exit(metric)
      end
    end
  end
end