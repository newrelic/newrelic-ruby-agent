require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper')) 
##require 'new_relic/agent/error_collector'
require 'test/unit'

    class NewRelic::Agent::ErrorCollectorTests < Test::Unit::TestCase
      
      def setup
        @error_collector = NewRelic::Agent::ErrorCollector.new(nil)
      end

      def test_simple
        @error_collector.notice_error('path', '/myurl/', {:x => 'y'}, Exception.new("message"))
        
        old_errors = []
        errors = @error_collector.harvest_errors(old_errors)
        
        assert_equal errors.length, 1
        
        err = errors.first
        assert_equal 'message', err.message 
        assert_equal 'y', err.params[:request_params][:x]
        assert err.params[:request_uri] == '/myurl/'
        assert err.path == 'path'
        assert err.exception_class == 'Exception'
        
        # the collector should now return an empty array since nothing
        # has been added since its last harvest
        errors = @error_collector.harvest_errors(nil)
        assert errors.length == 0
      end
      
      def test_collect_failover
        @error_collector.notice_error('first', nil, {:x => 'y'}, Exception.new("message"))
        
        errors = @error_collector.harvest_errors([])
        
        @error_collector.notice_error('second', nil, {:x => 'y'}, Exception.new("message"))
        @error_collector.notice_error('path', nil, {:x => 'y'}, Exception.new("message"))
        @error_collector.notice_error('path', nil, {:x => 'y'}, Exception.new("message"))
        
        errors = @error_collector.harvest_errors(errors)
        
        assert_equal 1, errors.length
        assert_equal 'first', errors.first.path

        # add two more
        @error_collector.notice_error('path', nil, {:x => 'y'}, Exception.new("message"))
        @error_collector.notice_error('last', nil, {:x => 'y'}, Exception.new("message"))
        
        errors = @error_collector.harvest_errors(nil)
        assert_equal 5, errors.length
        assert_equal 'second', errors.first.path
        assert_equal 'last', errors.last.path
        
      end
      
      def test_queue_overflow
        
        max_q_length = 20     # for some reason I can't read the constant in ErrorCollector
        
        silence_stream(::STDERR) do
         (max_q_length + 5).times do |n|
            @error_collector.notice_error("path", nil, {:x => n}, Exception.new("exception #{n}"))
          end
        end
        
        errors = @error_collector.harvest_errors([])
        assert errors.length == max_q_length 
        errors.each_index do |i|
          err = errors.shift
          assert_equal i.to_s, err.params[:request_params][:x], err.params.inspect
        end
      end
      
      # Why would anyone undef these methods?
      class TestClass
        undef to_s
        undef inspect
      end
      
      
      def test_supported_param_types
        
        types = [[1, '1'],
                 [1.1, '1.1'],
                 ['hi', 'hi'],
                 [:hi, :hi],
                 [Exception.new("test"), "#<Exception: test>"],
                 [TestClass.new, "#<NewRelic::Agent::ErrorCollectorTests::TestClass>"]
                ]
        
        
        types.each do |test|
          @error_collector.notice_error('path', nil, {:x => test[0]}, Exception.new("message"))
          
          assert_equal test[1], @error_collector.harvest_errors([])[0].params[:request_params][:x]
        end
      end
      
      
      def test_exclude
        @error_collector.ignore(["ActionController::RoutingError"])
        
        @error_collector.notice_error('path', nil, {:x => 'y'}, ActionController::RoutingError.new("message"))
        
        errors = @error_collector.harvest_errors([])
        
        assert_equal 0, errors.length
      end
      
      def test_exclude_block
        @error_collector.ignore_error_filter do |e|
          if e.is_a? ActionController::RoutingError
            nil
          else
            e
          end
        end
        
        @error_collector.notice_error('path', nil, {:x => 'y'}, ActionController::RoutingError.new("message"))
        
        errors = @error_collector.harvest_errors([])
        
        assert_equal 0, errors.length
      end

    end
