# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','data_container_tests'))
require 'new_relic/agent/error_event_aggregator'

module NewRelic
  module Agent
    class ErrorEventAggregatorTest < Minitest::Test
      def setup
        @error_event_aggregator = NewRelic::Agent::ErrorEventAggregator.new
        freeze_time
      end

      def create_container
        @error_event_aggregator
      end

      def populate_container(sampler, n)
        n.times do |i|
          error = NewRelic::NoticedError.new "Controller/blogs/index", RuntimeError.new("Big Controller")
          transaction = nil
          @error_event_aggregator.append_event error, transaction
        end
      end

      include NewRelic::DataContainerTests

      def test_generates_event_from_error
        error = NewRelic::NoticedError.new "Controller/blogs/index", RuntimeError.new("Big Controller")
        @error_event_aggregator.append_event error, nil
        errors = @error_event_aggregator.harvest!
        intrinsics, *_ = errors.first

        assert_equal "TransactionError", intrinsics[:type]
        assert_equal Time.now.to_f, intrinsics[:timestamp]
        assert_equal "RuntimeError", intrinsics[:errorClass]
        assert_equal "Big Controller", intrinsics[:errorMessage]
      end
    end
  end
end
