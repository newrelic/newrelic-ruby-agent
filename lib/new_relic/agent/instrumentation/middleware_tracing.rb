# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/method_tracer'
require 'new_relic/agent/transaction'
require 'new_relic/agent/transaction_state'
require 'new_relic/agent/instrumentation/queue_time'
require 'new_relic/agent/instrumentation/controller_instrumentation'

# This module is intended to be included into both MiddlewareProxy and our
# internal middleware classes.
#
# Host classes must define two methods:
#
# * target: returns the original middleware being traced
# * category: returns the category for the resulting agent transaction
#             should be either :middleware or :rack
# * transaction_options: returns an options hash to be passed to
#                        Transaction.start when tracing this middleware.
#
# The target may be self, in which case the host class should define a
# #traced_call method, instead of the usual #call.

module NewRelic
  module Agent
    module Instrumentation
      module MiddlewareTracing
        CAPTURED_REQUEST_KEY = 'newrelic.captured_request'.freeze unless defined?(CAPTURED_REQUEST_KEY)

        def _nr_has_middleware_tracing
          true
        end

        def build_transaction_options(env)
          if env[CAPTURED_REQUEST_KEY]
            transaction_options
          else
            env[CAPTURED_REQUEST_KEY] = true
            queue_timefrontend_timestamp = QueueTime.parse_frontend_timestamp(env)
            transaction_options.merge(
              :request          => ::Rack::Request.new(env),
              :apdex_start_time => queue_timefrontend_timestamp
            )
          end
        end

        def call(env)
          opts = build_transaction_options(env)
          state = NewRelic::Agent::TransactionState.tl_get

          begin
            Transaction.start(state, category, opts)
            if target == self
              traced_call(env)
            else
              target.call(env)
            end
          rescue => e
            NewRelic::Agent.notice_error(e)
            raise
          ensure
            Transaction.stop(state)
          end
        end
      end
    end
  end
end
