# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'test_helper'))
require 'new_relic/agent/instrumentation/sinatra'

class NewRelic::Agent::Instrumentation::SinatraTest < Test::Unit::TestCase
  class SinatraTestApp
    attr_accessor :request

    include NewRelic::Agent::Instrumentation::Sinatra
  end

  def test_newrelic_request_headers
    app = SinatraTestApp.new()
    expected_headers = {:fake => :header}
    app.request = mock('request', :env => expected_headers)

    assert_equal app.newrelic_request_headers, expected_headers
  end

  def test_transaction_naming
    assert_transaction_name "(unknown)", "(unknown)"

    # Sinatra < 1.4 style regexes
    assert_transaction_name "will_boom", "^/will_boom$"
    assert_transaction_name "hello/([^/?#]+)", "^/hello/([^/?#]+)$"

    # Sinatra 1.4 style regexs
    assert_transaction_name "will_boom", "\A/will_boom\z"
    assert_transaction_name "hello/([^/?#]+)", "\A/hello/([^/?#]+)\z"
  end

  def assert_transaction_name(expected, original)
    assert_equal expected, NewRelic::Agent::Instrumentation::Sinatra::NewRelic.transaction_name(original, nil)
  end

end
