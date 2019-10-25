# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/method_tracer'
require 'new_relic/agent/transaction'
require 'new_relic/agent/tracer'
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

          state = NewRelic::Agent::Tracer.state

          begin
            options = build_transaction_options(env, first_middleware)

            finishable = Tracer.start_transaction_or_segment(
              name: options[:transaction_name],
              category: category,
              options: options
            )

            events.notify(:before_call, env) if first_middleware

            result = (target == self) ? traced_call(env) : target.call(env)

            if first_middleware
              capture_response_attributes(state, result)
              events.notify(:after_call, env, result)
            end

            if first_middleware
              status, headers, response = *result
              lazy_response = response.respond_to?(:close)

              if lazy_response
                wrapped_response = StreamBodyProxy.new(response) do
                  finishable.finish if finishable
                end

                [status, headers, wrapped_response]
              else
                result
              end
            else
              result
            end
          rescue Exception => e
            NewRelic::Agent.notice_error(e)
            raise e
          ensure
            if finishable
              if first_middleware && lazy_response
                # NOOP: StreamBodyProxy handles this
              else
                finishable.finish
              end
            end
          end
        end

        def events
          NewRelic::Agent.instance.events
        end
      end

      class StreamBodyProxy # ideally this would inherit from < Rack::BodyProxy
        def initialize(body, &block)
          @body = body
          @block = block
          @closed = false
        end

        def respond_to?(method_name, include_all = false)
          case method_name
          when :to_ary, 'to_ary'
            return false
          end
          super or @body.respond_to?(method_name, include_all)
        end

        def close
          return if @closed

          close_segment = NewRelic::Agent::Tracer.start_segment(name: 'Middleware/Rack/StreamBodyProxy/close')
          @closed = true
          begin
            @body.close if @body.respond_to? :close
          rescue => e
            NewRelic::Agent.notice_error(e)
            raise
          ensure
            begin
              close_segment.finish
            ensure
              @block.call
            end
          end
        end

        def closed?
          @closed
        end

        def each
          segment = NewRelic::Agent::Tracer.start_segment(name: 'Middleware/Rack/StreamBodyProxy/body_each')

          @body.each { |body| yield body }
        rescue => e
          NewRelic::Agent.notice_error(e)
          raise
        ensure
          segment.finish
        end

        def method_missing(method_name, *args, &block)
          super if :to_ary == method_name
          @body.__send__(method_name, *args, &block)
        end
      end
    end
  end
end
