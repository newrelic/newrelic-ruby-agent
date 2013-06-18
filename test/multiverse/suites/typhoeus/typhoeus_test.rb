# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "typhoeus"
require "newrelic_rpm"
require "test/unit"
require "http_client_test_cases"

require File.join(File.dirname(__FILE__), "..", "..", "..", "agent_helper")

if Typhoeus::VERSION >= "0.5"

  class TyphoeusTest < Test::Unit::TestCase
    include HttpClientTestCases

    def client_name
      "Typhoeus"
    end

    def get_response(url=nil)
      Typhoeus::Request.get(url || default_url)
    end

    def head_response
      Typhoeus.head(default_url)
    end

    def post_response
      Typhoeus.post(default_url, :body => "")
    end

    def request_instance
      NewRelic::Agent::HTTPClients::TyphoeusHTTPRequest.new(Typhoeus::Request.new("http://newrelic.com"))
    end

    def response_instance
      NewRelic::Agent::HTTPClients::TyphoeusHTTPResponse.new(Typhoeus::Response.new)
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
