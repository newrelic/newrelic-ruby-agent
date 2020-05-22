# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require File.expand_path('../test_helper', __FILE__)

module NewRelic
  module Agent
    module InfiniteTracing
      class InfiniteTracingTest < Minitest::Test

        # Ensures we're tracking versions against agent's version.
        def test_version_matches_agent_version
          refute_nil NewRelic::Agent::InfiniteTracing::VERSION::STRING
          assert_equal NewRelic::VERSION::STRING, NewRelic::Agent::InfiniteTracing::VERSION::STRING
        end

        def test_span_events_fixtures_load
          span_event = span_event_fixture :single
          assert_kind_of Array, span_event
          assert_kind_of Hash, span_event[0]
          assert_kind_of Hash, span_event[1]
          assert_kind_of Hash, span_event[2]
        end

      end
    end
  end
end
