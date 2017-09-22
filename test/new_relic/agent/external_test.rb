# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/external'

module NewRelic
  module Agent
    class ExternalTest < Minitest::Test
      def test_start_segment_starts_an_external_segment
        args = ['Net::HTTP', 'https://example.com/foobar', 'GET']
        ::NewRelic::Agent::Transaction::Tracing.expects(:start_external_request_segment).with(*args)
        NewRelic::Agent::External.start_segment(library: args[0], uri: args[1], procedure: args[2])
      end
    end
  end
end