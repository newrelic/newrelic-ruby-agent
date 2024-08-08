# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module RdkafkaProducer
    module Prepend
      include NewRelic::Agent::Instrumentation::Rdkafka

      def produce(**kwargs)
        produce_with_new_relic(kwargs) do |headers|
          kwargs[:headers] = headers
          super
        end
      end
    end
  end

  module RdkafkaConsumer
    module Prepend
      include NewRelic::Agent::Instrumentation::Rdkafka

      def each
        super do |message|
          each_with_new_relic(message) do
            yield(message)
          end
        end
      end
    end
  end

  module RdkafkaConfig
    module Prepend
      include NewRelic::Agent::Instrumentation::RdkafkaConfig

      def producer(**kwargs)
        super.tap do |producer|
          set_nr_config(producer)
        end
      end

      def consumer(**kwargs)
        super.tap do |consumer|
          set_nr_config(consumer)
        end
      end
    end
  end
end
