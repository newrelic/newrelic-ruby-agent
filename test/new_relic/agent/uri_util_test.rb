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

  def filter(uri_string, opts={})
    NewRelic::Agent::URIUtil.filtered_uri_for(*dummy_request(uri_string, opts))
  end

  def test_filtered_uri_for
    uri = "http://foo.com/bar/baz"
    assert_equal("http://foo.com/bar/baz", filter(uri))
  end

  def test_filtered_uri_for_custom_port
    uri = "http://foo.com:1234/bar/baz"
    assert_equal("http://foo.com:1234/bar/baz", filter(uri))
  end

  def test_filtered_uri_omits_query_params
    uri = "http://foo.com/bar/baz?a=1&b=2"
    assert_equal("http://foo.com/bar/baz", filter(uri))
  end

  def test_filtered_uri_omits_fragment
    uri = "http://foo.com/bar/baz#fragment"
    assert_equal("http://foo.com/bar/baz", filter(uri, :path => '/bar/baz#fragment'))
  end

  def test_filtered_uri_omits_query_params_and_fragment
    uri = "http://foo.com/bar/baz?a=1&b=2#fragment"
    assert_equal("http://foo.com/bar/baz", filter(uri, :path => '/bar/baz?a=1&b=2#fragment'))
  end

  def test_filtered_uri_reflects_use_of_ssl
    uri = 'https://foo.com/bar/baz'
    assert_equal("https://foo.com/bar/baz", filter(uri, :use_ssl => true))
  end

  def test_filtered_uri_reflects_use_of_ssl_with_custom_port
    uri = 'https://foo.com:9999/bar/baz'
    assert_equal("https://foo.com:9999/bar/baz", filter(uri, :use_ssl => true))
  end

  def test_filtered_uri_for_with_full_uri_request_path
    uri = "http://foo.com/bar/baz?a=1&b=2#fragment"
    assert_equal("http://foo.com/bar/baz", filter(uri, :path => uri))
  end

  def test_filtered_uri_for_with_full_uri_request_path_https
    uri = "https://foo.com/bar/baz?a=1&b=2#fragment"
    assert_equal("https://foo.com/bar/baz", filter(uri, :path => uri, :use_ssl => true))
  end

  def test_strips_credentials_embedded_in_uri
    uri = "http://user:pass@foo.com/bar/baz"
    assert_equal("http://foo.com/bar/baz", filter(uri, :path => uri))
  end
end
