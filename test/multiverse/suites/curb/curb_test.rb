# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'curb'

require 'newrelic_rpm'
require 'test/unit'
require 'http_client_test_cases'
require 'new_relic/agent/http_clients/curb_wrappers'

require File.join(File.dirname(__FILE__), "..", "..", "..", "agent_helper")

class CurbTest < Test::Unit::TestCase

  #
  # Tests
  #

  include HttpClientTestCases


  def test_shouldnt_clobber_existing_header_callback
    headers = []
    Curl::Easy.http_get( default_url ) do |handle|
      handle.on_header do |header|
        headers << header
        header.length
      end
    end

    assert_not_empty headers
  end

  def test_shouldnt_clobber_existing_completion_callback
    completed = false
    Curl::Easy.http_get( default_url ) do |handle|
      handle.on_complete do
        completed = true
      end
    end

    assert completed, "completion block was never run"
  end


  def test_get_works_with_the_shortcut_api
    # Override the mechanism for getting a response and run the test_get test
    # again
    def self.get_response
      Curl.get( default_url )
    end

    test_get
  end


  def test_background_works_with_the_shortcut_api
    # Override the mechanism for getting a response and run the test_get test
    # again
    def self.get_response
      Curl.get( default_url )
    end

    test_background
  end


  # Curl.head is broken in 0.8.4 (https://github.com/taf2/curb/pull/148), but if
  # it ever gets fixed, then this test should be uncommented.

  # def test_head_works_with_the_shortcut_api
  #   # Override the mechanism for getting a response and run the test_get test
  #   # again
  #   def self.head_response
  #     Curl.head( default_url )
  #   end
  # 
  #   test_head
  # end

  def test_doesnt_propagate_errors_in_instrumentation
    NewRelic::Agent::CrossAppTracing.stubs( :start_trace ).
      raises( StandardError, "something bad happened" )

    res = Curl::Easy.http_get( default_url )

    assert_kind_of Curl::Easy, res
  end


  #
  # Helper functions
  #

  def client_name
    "Curb"
  end

  def get_response(url=nil)
    Curl::Easy.http_get( url || default_url )
  end

  def head_response
    Curl::Easy.http_head( default_url )
  end

  def post_response
    Curl::Easy.http_post( default_url, '' )
  end

  def body(res)
    res.body_str
  end

  def request_instance
    NewRelic::Agent::HTTPClients::CurbRequest.new(nil)
  end

  def response_instance
    NewRelic::Agent::HTTPClients::CurbResponse.new(nil)
  end

end

