# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

require 'new_relic/agent/transaction'
require 'new_relic/agent/transaction/external_request_segment'

module NewRelic
  module Agent
    class Transaction
      class ExternalRequestSegmentTest < Minitest::Test
        def test_generates_expected_name
          segment = ExternalRequestSegment.new "Typhoeus", "http://remotehost/blogs/index", "GET"
          assert_equal "External/remotehost/Typhoeus/GET", segment.name
        end
      end
    end
  end
end
