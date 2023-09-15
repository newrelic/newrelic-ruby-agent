# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'net_http_test_cases'
#require_relative '../../../helpers/misc'

class Testbed
  include NewRelic::Agent::Instrumentation::NetHTTP

  def address; 'localhost'; end
  def use_ssl?; false; end
  def port; 1138; end
end

class NetHttpTest < Minitest::Test
  # This test will see that `segment` is `nil` within the `ensure` block of
  # `request_with_tracing` to confirm that we check for `nil` prior to
  # attempting to call `#finish` on `segment`.
  # https://github.com/newrelic/newrelic-ruby-agent/issues/2213
  def test_segment_might_fail_to_start
    t = Testbed.new
    response = 'I am a response, which an exception will prevent you from receiving unless you handle a nil segment'

    segment = nil
    def segment.add_request_headers(_request); end
    def segment.process_response_headers(_response); end

    request = Minitest::Mock.new
    2.times { request.expect :path, '/' }
    request.expect :method, 'GET'

    NewRelic::Agent::Tracer.stub :start_external_request_segment, segment do
      result = t.request_with_tracing(request) { response }

      assert_equal response, result
    end
  end
end
