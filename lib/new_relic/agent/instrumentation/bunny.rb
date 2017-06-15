# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :bunny

  depends_on do
    defined?(Bunny)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Bunny instrumentation'
    require 'new_relic/agent/cross_app_tracing'
  end

  executes do
    module Bunny
      class Exchange

        alias_method :publish_without_new_relic, :publish

        def publish payload, opts = {}
          destination = name.empty? ? NewRelic::Agent::Instrumentation::Bunny::DEFAULT : name

          segment = NewRelic::Agent::Transaction.start_amqp_publish_segment(
            library: NewRelic::Agent::Instrumentation::Bunny::LIBRARY,
            destination_name: destination,
            headers: opts[:headers],
            routing_key: opts[:routing_key] || opts[:key],
            reply_to: opts[:reply_to],
            correlation_id: opts[:correlation_id],
            exchange_type: type
          )

          begin
            publish_without_new_relic payload, opts
          ensure
            segment.finish if segment
          end
        end
      end
    end
  end
end

module NewRelic
  module Agent
    module Instrumentation
      module Bunny
        LIBRARY = 'RabbitMQ'.freeze
        DEFAULT = 'Default'.freeze
      end
    end
  end
end
