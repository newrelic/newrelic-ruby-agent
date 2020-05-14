# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require File.expand_path('../../../../test_helper', __FILE__)

module NewRelic
  module Agent
    module InfiniteTracing
      class AgentIntegrationTest < Minitest::Test
        def test_injects_infinite_tracer
          assert ::NewRelic::Agent.instance, "expected to get an Agent instance"
          assert ::NewRelic::Agent.instance.instance_variable_get :@infinite_tracer
        end
      end
    end
  end
end
