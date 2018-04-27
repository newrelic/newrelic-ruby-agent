# frozen_string_literal: true

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
        TXN_STARTED_KEY = 'newrelic.transaction_started'.freeze

        def _nr_has_middleware_tracing
          true
        end

        def build_transaction_options(env, first_middleware)
          opts = transaction_options
          opts = merge_first_middleware_options(opts, env) if first_middleware
          opts
        end

        def merge_first_middleware_options(opts, env)
          opts[:apdex_start_time] = QueueTime.parse_frontend_timestamp(env)
          # this case is for the rare occasion that an app is using Puma::Rack
          # without having ::Rack as a dependency
          opts[:request] = ::Rack::Request.new(env) if defined? ::Rack
          opts
        end

        def note_transaction_started(env)
          env[TXN_STARTED_KEY] = true unless env[TXN_STARTED_KEY]
        end

        def capture_http_response_code(state, result)
          if result.is_a?(Array) && state.current_transaction
            state.current_transaction.http_response_code = result[0]
          end
        end

        CONTENT_TYPE = 'Content-Type'.freeze

        def capture_response_content_type(state, result)
          if result.is_a?(Array) && state.current_transaction
            _, headers, _ = result
            state.current_transaction.response_content_type = headers[CONTENT_TYPE]
          end
        end

        CONTENT_LENGTH = 'Content-Length'.freeze

        def capture_response_content_length(state, result)
          if result.is_a?(Array) && state.current_transaction
            _, headers, _ = result
            state.current_transaction.response_content_length = headers[CONTENT_LENGTH]
          end
        end

        def capture_response_attributes(state, result)
          capture_http_response_code(state, result)
          capture_response_content_type(state, result)
          capture_response_content_length(state, result)
        end

        def call(env)
          first_middleware = note_transaction_started(env)

          state = NewRelic::Agent::TransactionState.tl_get

          begin
            Transaction.start(state, category, build_transaction_options(env, first_middleware))
            events.notify(:before_call, env) if first_middleware

            result = (target == self) ? traced_call(env) : target.call(env)

            if first_middleware
              capture_response_attributes(state, result)
              events.notify(:after_call, env, result)
            end

            result
          rescue Exception => e
            NewRelic::Agent.notice_error(e)
            raise e
          ensure
            Transaction.stop(state)
          end
        end

        def events
          NewRelic::Agent.instance.events
        end
      end
    end
  end
end
