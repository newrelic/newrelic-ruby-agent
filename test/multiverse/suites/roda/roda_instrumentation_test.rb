# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../../../lib/new_relic/agent/instrumentation/roda/instrumentation'

# require 'lib/new_relic/agent/instrumentation/roda/roda_transaction_namer'
# require 'roda'

# class RodaTestApp < Roda
#   post '/test' do
#     'test'
#   end
# end

class RodaInstrumentationTest < Minitest::Test
  # include MultiverseHelpers

  def test_roda_defined
    assert_equal 1, 1
  end

  def test_roda_undefined
  end

  def test_roda_version_supported
  end

  def test_roda_version_unspoorted
  end

  def test_build_rack_app_defined
  end

  def test_build_rack_app_undefined
  end

  def test_roda_handle_main_route_defined
  end

  def test_roda_handle_main_route_undefined
  end

  # patched methods
  def test_roda_handle_main_route
  end

  def test_build_rack_app
  end

  # instrumentation file
  def test_newrelic_middlewares_agenthook_inserted
  end

  def test_newrelic_middlewares_agenthook_not_inserted
  end

  def test_newrelic_middlewares_all_inserted
    # should have a helper method out there - last_transaction_trace // event? last_response
    # get last t
  end

  def test_build_rack_app_with_tracing_unless_middleware_disabled
  end

  def test_rack_request_params_returns_rack_params
  end

  def test_rack_request_params_fails
  end

  def test_roda_handle_main_route_with_tracing
    # should have a helper method out there - last_transaction_trace // event? last_response
    # get last txn, is the name correct? are other things correct about that txn
  end

  # Transaction File

  def test_transaction_name_standard_request
  end

  def test_transaction_no_request_path
  end

  def test_transaction_name_regex_clears_extra_backslashes
  end

  def test_transaction_name_path_name_empty
  end

  def test_transaction_name_verb_nil
  end

  def test_http_verb_does_not_respond_to_request_method
  end
end
