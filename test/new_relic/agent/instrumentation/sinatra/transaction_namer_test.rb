# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'test_helper'))
require 'new_relic/agent/instrumentation/sinatra/transaction_namer'

module NewRelic
  module Agent
    module Instrumentation
      module Sinatra

        class TransactionNamerTest < Minitest::Test

          def test_transaction_name_for_route
            env = { "newrelic.last_route" => /^\/the_route$/}
            request = stub(:request_method => "GET")
            result = TransactionNamer.transaction_name_for_route(env, request)
            assert_equal "GET the_route", result
          end

          def test_transaction_name_for_route_padrino
            env = {}
            route = stub(:original_path => "/path/:id")
            request = stub(:route_obj => route, :request_method => "GET")
            result = TransactionNamer.transaction_name_for_route(env, request)

            assert_equal "GET path/:id", result
          end

          def test_transaction_name_for_root_route
            env = { "newrelic.last_route" => /\A\/\z/}
            request = stub(:request_method => "GET")
            result = TransactionNamer.transaction_name_for_route(env, request)
            assert_equal "GET /", result
          end

          def test_transaction_name_for_route_without_routes
            assert_nil TransactionNamer.transaction_name_for_route({}, nil)
          end

          def test_basic_sinatra_naming
            assert_transaction_name "(unknown)", "(unknown)"

            # Sinatra < 1.4 style regexes
            assert_transaction_name "will_boom", "^/will_boom$"
            assert_transaction_name "hello/([^/?#]+)", "^/hello/([^/?#]+)$"

            # Sinatra 1.4 style regexs
            assert_transaction_name "will_boom", "\A/will_boom\z"
            assert_transaction_name "hello/([^/?#]+)", "\A/hello/([^/?#]+)\z"
          end

          def assert_transaction_name(expected, original)
            assert_equal expected, TransactionNamer.transaction_name(original, nil)
          end

        end
      end
    end
  end
end
