# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','data_container_tests'))

module NewRelic
  module Agent
    class ErrorTraceAggregatorTest < Minitest::Test
      def setup
        @error_trace_aggregator = NewRelic::Agent::ErrorTraceAggregator.new ErrorCollector::MAX_ERROR_QUEUE_LENGTH
      end

     # Helpers for DataContainerTests

      def create_container
        ErrorTraceAggregator.new ErrorCollector::MAX_ERROR_QUEUE_LENGTH
      end

      def populate_container(aggregator, n)
        n.times do |i|
          error = NewRelic::NoticedError.new 'path', 'yay errors'
          aggregator.add_to_error_queue error
        end
      end

      include NewRelic::DataContainerTests

      def test_simple
        notice_error(StandardError.new("message"),
                                      :uri => '/myurl/',
                                      :metric => 'path')

        errors = error_trace_aggregator.harvest!

        assert_equal errors.length, 1

        err = errors.first
        assert_equal 'message', err.message
        assert_equal '/myurl/', err.request_uri
        assert_equal 'path', err.path
        assert_equal 'StandardError', err.exception_class_name

        # the collector should now return an empty array since nothing
        # has been added since its last harvest
        errors = error_trace_aggregator.harvest!
        assert_empty errors
      end

      def test_collect_failover
        notice_error(StandardError.new("message"), :metric => 'first')

        errors = error_trace_aggregator.harvest!

        notice_error(StandardError.new("message"), :metric => 'second')
        notice_error(StandardError.new("message"), :metric => 'path')
        notice_error(StandardError.new("message"), :metric => 'last')

        error_trace_aggregator.merge!(errors)
        errors = error_trace_aggregator.harvest!

        assert_equal 4, errors.length
        assert_equal_unordered(%w(first second path last), errors.map { |e| e.path })

        notice_error(StandardError.new("message"), :metric => 'first')
        notice_error(StandardError.new("message"), :metric => 'last')

        errors = error_trace_aggregator.harvest!
        assert_equal 2, errors.length
        assert_equal 'first', errors.first.path
        assert_equal 'last', errors.last.path
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
        [:hi, 'hi'],
        [StandardError.new("test"), "#<StandardError>"],
        [TestClass.new, "#<NewRelic::Agent::ErrorTraceAggregatorTest::TestClass>"]
        ]

        types.each do |test|
          notice_error(StandardError.new("message"),
                                        :metric => 'path',
                                        :custom_params => {:x => test[0]})
          error = error_trace_aggregator.harvest![0].to_collector_array
          actual = error.last["userAttributes"]["x"]
          assert_equal test[1], actual
        end
      end

      def test_obfuscates_error_messages_when_high_security_is_set
        with_config(:high_security => true) do
          notice_error(StandardError.new("YO SQL BAD: serect * flom test where foo = 'bar'"))
          notice_error(StandardError.new("YO SQL BAD: serect * flom test where foo in (1,2,3,4,5)"))

          errors = error_trace_aggregator.harvest!

          assert_equal(NewRelic::NoticedError::STRIPPED_EXCEPTION_REPLACEMENT_MESSAGE, errors[0].message)
          assert_equal(NewRelic::NoticedError::STRIPPED_EXCEPTION_REPLACEMENT_MESSAGE, errors[1].message)
        end
      end

      def test_over_queue_limit_negative
        refute error_trace_aggregator.over_queue_limit?(nil)
      end

      def test_over_queue_limit_positive
        expects_logging(:warn, includes('The error reporting queue has reached 20'))
        21.times do
          error = stub(:message => "", :is_internal => false)
          error_trace_aggregator.add_to_error_queue(error)
        end

        assert error_trace_aggregator.over_queue_limit?('hooray')
      end

      def test_queue_overflow
        max_q_length = ErrorCollector::MAX_ERROR_QUEUE_LENGTH

        silence_stream(::STDOUT) do
         (max_q_length + 5).times do |n|
            notice_error(StandardError.new("exception #{n}"),
                                          :metric => "path",
                                          :custom_params => {:x => n})
          end
        end

        errors = error_trace_aggregator.harvest!
        assert errors.length == max_q_length
        errors.each_index do |i|
          error  = errors.shift
          actual = error.to_collector_array.last["userAttributes"]["x"]
          assert_equal i.to_s, actual
        end
      end

      def create_noticed_error(exception, options = {})
        path = options.delete(:metric)
        noticed_error = NewRelic::NoticedError.new(path, exception)
        noticed_error.request_uri = options.delete(:uri)
        noticed_error.attributes  = options.delete(:attributes)
        noticed_error.attributes_from_notice_error = options.delete(:custom_params) || {}
        noticed_error.attributes_from_notice_error.merge!(options)
        noticed_error
      end

      def notice_error(exception, options = {})
        error = create_noticed_error(exception, options)
        @error_trace_aggregator.add_to_error_queue error
      end

      def error_trace_aggregator
        @error_trace_aggregator
      end
    end
  end
end
