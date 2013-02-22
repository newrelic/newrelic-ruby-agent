# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
module NewRelic
  module Agent
    class ShimAgentTest < Test::Unit::TestCase

      def setup
        super
        @agent = NewRelic::Agent::ShimAgent.new
      end

      def test_merge_data_from
        assert_equal(nil, @agent.merge_data_from(mock('metric data')))
      end
    end
  end
end
