# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'em-http-request'
require 'newrelic_rpm'
require 'http_client_test_cases'
require 'fiber' if RUBY_VERSION >= "1.9"

class EMHTTPRequestTest < Minitest::Test
  include HttpClientTestCases

  def client_name
    "EMHTTPRequest"
  end

  def get_response(url=nil, headers=nil)
    request_with_fiber(default_url, :get, headers)
  end

  def head_response
    request_with_fiber(default_url, :head)
  end

  def post_response
    request_with_fiber(default_url, :post)
  end

  def put_response
    request_with_fiber(default_url, :put)
  end

  def delete_response
    request_with_fiber(default_url, :delete)
  end

  def request_instance
    request = HttpClientOptions.new(URI.parse("http://newrelic.com"), {}, nil)
    NewRelic::Agent::HTTPClients::EMHTTPRequest.new(request)
  end

  def response_instance(headers = {})
    NewRelic::Agent::HTTPClients::EMHTTPResponse.new(headers)
  end

  def _method_nil
  end

  def setup_with_em
    test_methods = EMHTTPRequestTest.instance_methods.select do |method|
      method[0..4] == "test_"
    end

    excluded_methods = []

    if RUBY_VERSION < "1.9"
      available_test_methods = [
        :test_validate_request_wrapper,
        :test_validate_response_wrapper,
        :test_request_headers_for_missing_key,
        :test_response_headers_for_missing_key,
        :test_response_wrapper_ignores_case_in_header_keys
      ]

      # Skipping tests because tests have implemented with fiber but ruby 1.8
      # does not support fiber.
      excluded_methods = test_methods - available_test_methods
    else
      if RUBY_VERSION < "2.0"
        # Skipping tests below, because of ruby 1.9 fiber / thread object
        # access issue, the tests cannot be performed correct.
        excluded_methods += [
          :test_instrumentation_with_crossapp_enabled_records_crossapp_metrics_if_header_present,
          :test_crossapp_metrics_allow_valid_utf8_characters,
          :test_includes_full_url_in_transaction_trace,
          :test_transactional_metrics
        ]
        test_methods -= excluded_methods
      end

      # Add EventMachine block to all existing test, because current
      # HttpClientTestCases tests are not built for event driven manner,
      # we need to wrap test methods with EventMachine loop.
      test_methods.each { |method| add_em_block(method) }
    end

    excluded_methods.each { |method| instance_eval %Q{ alias #{method} _method_dummy } }
    setup_without_em
  end

  alias :setup_without_em :setup
  alias :setup :setup_with_em

  private

  def request_with_fiber(url, method, headers = nil)
    f = Fiber.current
    http = EventMachine::HttpRequest.new(url).send(method, { :head => headers })
    http.callback { f.resume(http) }
    http.error { f.resume(http) }
    Fiber.yield
  end

  def add_em_block(method_name)
    traced_method = _method_with_em(method_name)
    instance_eval traced_method, __FILE__, __LINE__
    instance_eval %Q{
      alias #{_method_name_without_em(method_name)} #{method_name}
      alias #{method_name} #{_method_name_with_em(method_name)}
    }
  end

  def _method_dummy
  end

  def _method_name_without_em(method_name)
    "_#{_sanitize_name(method_name)}_without_em"
  end

  def _method_name_with_em(method_name)
    "_#{_sanitize_name(method_name)}_with_em"
  end

  def _sanitize_name(name)
    name.to_s.tr_s("^a-zA-Z0-9", "_")
  end

  def _method_with_em(method_name)
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
