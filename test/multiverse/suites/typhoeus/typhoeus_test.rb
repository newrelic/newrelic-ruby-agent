# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "typhoeus"
require "newrelic_rpm"
require "test/unit"
require "http_client_test_cases"

require File.join(File.dirname(__FILE__), "..", "..", "..", "agent_helper")

if NewRelic::Agent::Instrumentation::TyphoeusTracing.is_supported_version?

  class TyphoeusTest < MiniTest::Unit::TestCase
    include HttpClientTestCases

    USE_SSL_VERIFYPEER_VERSION = NewRelic::VersionNumber.new("0.5.0")

    def ssl_option
      if NewRelic::VersionNumber.new(Typhoeus::VERSION) >= USE_SSL_VERIFYPEER_VERSION
        { :ssl_verifypeer => false }
      else
        { :disable_ssl_peer_verification => true }
      end
    end

    def client_name
      "Typhoeus"
    end

    # We use the Typhoeus::Request rather than right on Typhoeus to support
    # prior to convenience methods being added on the top-level module (0.5.x)
    def get_response(url=nil, headers=nil)
      options = {:headers => headers}.merge(ssl_option)
      Typhoeus::Request.get(url || default_url, options)
    end

    def head_response
      Typhoeus::Request.head(default_url, ssl_option)
    end

    def post_response
      Typhoeus::Request.post(default_url, ssl_option.merge(:body => ""))
    end

    def put_response
      Typhoeus::Request.put(default_url, ssl_option.merge(:body => ""))
    end

    def delete_response
      Typhoeus::Request.delete(default_url, ssl_option)
    end

    def request_instance
      NewRelic::Agent::HTTPClients::TyphoeusHTTPRequest.new(Typhoeus::Request.new("http://newrelic.com"))
    end

    def response_instance(headers = {})
      headers = headers.map do |k,v|
        "#{k}: #{v}"
      end.join("\r\n")

      NewRelic::Agent::HTTPClients::TyphoeusHTTPResponse.new(Typhoeus::Response.new(:response_headers => headers))
    end


    def test_hydra
      in_transaction("test") do
        hydra = Typhoeus::Hydra.new
        5.times { hydra.queue(Typhoeus::Request.new(default_url, ssl_option)) }
        hydra.run

        last_segment = find_last_transaction_segment()
        assert_equal "External/Multiple/Typhoeus::Hydra/run", last_segment.metric_name
      end
    end
  end

else

  class TyphoeusNotInstrumented < MiniTest::Unit::TestCase
    def test_works_without_instrumentation
      # Typhoeus.get wasn't supported back before 0.5.x
      Typhoeus::Request.get("http://localhost/not/there")
      assert_metrics_not_recorded(["External/all"])
    end
  end

end
