# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'em-http-request'
require 'newrelic_rpm'
require 'http_client_test_cases'
require 'fiber'
require 'set'

class EMHTTPRequestTest < Minitest::Test
  include HttpClientTestCases

  def client_name
    "EMHTTPRequest"
  end

  def get_response(url=nil, headers=nil)
    f = Fiber.current
    http = EventMachine::HttpRequest.new(url || default_url).get :head => headers
    http.callback { f.resume(http) }
    http.error { f.resume(http) }
    Fiber.yield
  end

  def head_response
    f = Fiber.current
    http = EventMachine::HttpRequest.new(default_url).head
    http.callback { f.resume(http) }
    http.error { f.resume(http) }
    Fiber.yield
  end

  def post_response
    f = Fiber.current
    http = EventMachine::HttpRequest.new(default_url).post
    http.callback { f.resume(http) }
    http.error { f.resume(http) }
    Fiber.yield
  end

  def put_response
    f = Fiber.current
    http = EventMachine::HttpRequest.new(default_url).put
    http.callback { f.resume(http) }
    http.error { f.resume(http) }
    Fiber.yield
  end

  def delete_response
    f = Fiber.current
    http = EventMachine::HttpRequest.new(default_url).delete
    http.callback { f.resume(http) }
    http.error { f.resume(http) }
    Fiber.yield
  end

  def request_instance
    request = HttpClientOptions.new(URI.parse("http://newrelic.com"), {}, nil)
    NewRelic::Agent::HTTPClients::EMHTTPRequest.new(request)
  end

  def response_instance(headers = {})
    NewRelic::Agent::HTTPClients::EMHTTPResponse.new(headers)
  end

  def _method_dummy
  end

  def setup_with_em
    excluded_methods = Set.new [
      :test_transactional_metrics,
      :test_instrumentation_with_crossapp_enabled_records_crossapp_metrics_if_header_present,
      :test_crossapp_metrics_allow_valid_utf8_characters,
      :test_includes_full_url_in_transaction_trace,
      :test_failure_to_add_tt_node_doesnt_append_params_to_wrong_segment,
      :test_still_records_tt_node_when_request_fails
    ]

    test_methods = EMHTTPRequestTest.instance_methods.select do |method|
      method[0..3] == "test" && !excluded_methods.include?(method)
    end

    test_methods.each { |method| add_em_block(method) }
    excluded_methods.each { |method| instance_eval %Q{ alias #{method} _method_dummy } }
    setup_without_em
  end

  alias :setup_without_em :setup
  alias :setup :setup_with_em

  def add_em_block(method_name)
    traced_method = method_with_em(method_name)
    instance_eval traced_method, __FILE__, __LINE__
    instance_eval %Q{
      alias #{_method_name_without_em(method_name)} #{method_name}
      alias #{method_name} #{_method_name_with_em(method_name)}
    }
  end

  def _method_name_without_em(method_name)
    "_#{_sanitize_name(method_name)}_without_em"
  end

  def _method_name_with_em(method_name)
    "_#{_sanitize_name(method_name)}_with_em"
  end

  def _sanitize_name(name)
    name.to_s.tr_s('^a-zA-Z0-9', '_')
  end

  def method_with_em(method_name)
    "def #{_method_name_with_em(method_name)}
      EventMachine.run do
        Fiber.new {
          #{_method_name_without_em(method_name)}\n
          EventMachine.stop
        }.resume
      end
    end"
  end

  def body(res)
    res.response
  end
end
