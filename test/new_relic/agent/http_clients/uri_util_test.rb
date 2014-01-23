# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/http_clients/uri_util'

class URIUtilTest < Minitest::Test

  def test_filter_uri
    assert_filtered("http://foo.com/bar/baz",
                    "http://foo.com/bar/baz")
  end

  def test_filter_uri_custom_port
    assert_filtered("http://foo.com:1234/bar/baz",
                    "http://foo.com:1234/bar/baz")
  end

  def test_filtered_uri_omits_query_params
    assert_filtered("http://foo.com/bar/baz?a=1&b=2",
                    "http://foo.com/bar/baz")
  end

  def test_filtered_uri_omits_fragment
    assert_filtered("http://foo.com/bar/baz#fragment",
                    "http://foo.com/bar/baz")
  end

  def test_filtered_uri_omits_query_params_and_fragment
    assert_filtered("http://foo.com/bar/baz?a=1&b=2#fragment",
                    "http://foo.com/bar/baz")
  end

  def test_filtered_uri_reflects_use_of_ssl
    assert_filtered('https://foo.com/bar/baz',
                    "https://foo.com/bar/baz")
  end

  def test_filtered_uri_reflects_use_of_ssl_with_custom_port
    assert_filtered('https://foo.com:9999/bar/baz',
                    "https://foo.com:9999/bar/baz")
  end

  def test_filter_uri_with_full_uri_request_path
    assert_filtered("http://foo.com/bar/baz?a=1&b=2#fragment",
                    "http://foo.com/bar/baz")
  end

  def test_filter_uri_with_full_uri_request_path_https
    assert_filtered("https://foo.com/bar/baz?a=1&b=2#fragment",
                    "https://foo.com/bar/baz")
  end

  def test_strips_credentials_embedded_in_uri
    assert_filtered("http://user:pass@foo.com/bar/baz",
                    "http://foo.com/bar/baz")
  end

  def assert_filtered(original, expected)
    assert_equal(expected, NewRelic::Agent::HTTPClients::URIUtil.filter_uri(URI(original)))
  end

end
