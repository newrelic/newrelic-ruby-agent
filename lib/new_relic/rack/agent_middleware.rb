# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction_state'
require 'new_relic/agent/instrumentation/controller_instrumentation'
require 'new_relic/agent/instrumentation/middleware_tracing'

module NewRelic
  module Rack
    class AgentMiddleware
      include Agent::Instrumentation::MiddlewareTracing

      attr_reader :transaction_options, :category, :target

      def initialize(app, options={})
        @app = app
        @category = :middleware
        @target   = self
        @transaction_options = {
          :transaction_name => build_transaction_name
        }
      end

      def build_transaction_name
        prefix = ::NewRelic::Agent::Instrumentation::ControllerInstrumentation::TransactionNamer.prefix_for_category(nil, @category)
        "#{prefix}#{self.class.name}/call"
      end
    end
  end
end
