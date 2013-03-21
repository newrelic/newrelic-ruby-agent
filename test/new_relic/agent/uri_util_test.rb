# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/agent_logger'
require 'new_relic/agent/null_logger'

class URIUtilTest < Test::Unit::TestCase
  def setup
    fixture_tcp_socket(nil)
  end

  def dummy_request(uri_string, opts={})
    uri = URI(uri_string)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = opts.has_key?(:use_ssl) ? opts[:use_ssl] : false
    req = Net::HTTP::Get.new(opts[:path] || uri.request_uri)
    [http, req]
  end

  def test_filtered_uri_for
    uri = "http://foo.com/bar/baz"
    filtered = NewRelic::Agent::URIUtil.filtered_uri_for(*dummy_request(uri))
    assert_equal("http://foo.com/bar/baz", filtered)
  end

  def test_filtered_uri_for_custom_port
    uri = "http://foo.com:1234/bar/baz"
    filtered = NewRelic::Agent::URIUtil.filtered_uri_for(*dummy_request(uri))
    assert_equal("http://foo.com:1234/bar/baz", filtered)
  end

  def test_filtered_uri_omits_query_params
    uri = "http://foo.com/bar/baz?a=1&b=2"
    filtered = NewRelic::Agent::URIUtil.filtered_uri_for(*dummy_request(uri))
    assert_equal("http://foo.com/bar/baz", filtered)
  end

  def test_filtered_uri_omits_fragment
    uri = "http://foo.com/bar/baz#fragment"
    filtered = NewRelic::Agent::URIUtil.filtered_uri_for(*dummy_request(uri, :path => '/bar/baz#fragment'))
    assert_equal("http://foo.com/bar/baz", filtered)
  end

  def test_filtered_uri_omits_query_params_and_fragment
    uri = "http://foo.com/bar/baz?a=1&b=2#fragment"
    filtered = NewRelic::Agent::URIUtil.filtered_uri_for(*dummy_request(uri, :path => '/bar/baz?a=1&b=2#fragment'))
    assert_equal("http://foo.com/bar/baz", filtered)
  end

  def test_filtered_uri_reflects_use_of_ssl
    uri = 'https://foo.com/bar/baz'
    conn, req = dummy_request(uri, :use_ssl => true)
    filtered = NewRelic::Agent::URIUtil.filtered_uri_for(conn, req)
    assert_equal("https://foo.com/bar/baz", filtered)
  end

  def test_filtered_uri_reflects_use_of_ssl_with_custom_port
    uri = 'https://foo.com:9999/bar/baz'
    conn, req = dummy_request(uri, :use_ssl => true)
    filtered = NewRelic::Agent::URIUtil.filtered_uri_for(conn, req)
    assert_equal("https://foo.com:9999/bar/baz", filtered)
  end
end
