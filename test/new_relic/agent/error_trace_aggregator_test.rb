# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','data_container_tests'))

module NewRelic
  module Agent
    class ErrorTraceAggregatorTest < Minitest::Test
      def setup
        @aggregator = ErrorTraceAggregator.new(20)
      end

      def test_over_queue_limit_negative
        refute @aggregator.over_queue_limit?(nil)
      end

      def test_over_queue_limit_positive
        expects_logging(:warn, includes('The error reporting queue has reached 20'))
        21.times do
          error = stub(:message => "", :is_internal => false)
          @aggregator.add_to_error_queue(error)
        end

        assert @aggregator.over_queue_limit?('hooray')
      end
    end
  end
end