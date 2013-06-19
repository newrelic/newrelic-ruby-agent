# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "typhoeus"
require "newrelic_rpm"
require "test/unit"
require "http_client_test_cases"

require File.join(File.dirname(__FILE__), "..", "..", "..", "agent_helper")

if Typhoeus::VERSION >= NewRelic::Agent::Instrumentation::TyphoeusTracing::EARLIEST_VERSION

  class TyphoeusTest < Test::Unit::TestCase
    include HttpClientTestCases

    def client_name
      "Typhoeus"
    end

    # We use the Typhoeus::Request rather than right on Typhoeus to support
    # prior to convenience methods being added on the top-level module (0.5.x)
    def get_response(url=nil)
      Typhoeus::Request.get(url || default_url)
    end

    def head_response
      Typhoeus::Request.head(default_url)
    end

    def post_response
      Typhoeus::Request.post(default_url, :body => "")
    end

    def request_instance
      NewRelic::Agent::HTTPClients::TyphoeusHTTPRequest.new(Typhoeus::Request.new("http://newrelic.com"))
    end

    def response_instance
      NewRelic::Agent::HTTPClients::TyphoeusHTTPResponse.new(Typhoeus::Response.new)
    end


    def test_hydra
      in_transaction("test") do
        hydra = Typhoeus::Hydra.new
        5.times { hydra.queue(Typhoeus::Request.new(default_url)) }
        hydra.run

        last_segment = find_last_transaction_segment()
        assert_equal "External/Multiple/Typhoeus::Hydra/run", last_segment.metric_name
      end
    end
  end

else

  class TyphoeusNotInstrumented < Test::Unit::TestCase
    def test_works_without_instrumentation
      # Typhoeus.get wasn't supported back before 0.5.x
      Typhoeus::Request.get("http://localhost/not/there")
      assert_metrics_not_recorded(["External/all"])
    end
  end

end
