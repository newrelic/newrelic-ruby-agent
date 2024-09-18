# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module RubyKafkaProducer
    module Prepend
      include NewRelic::Agent::Instrumentation::RubyKafka

      def produce(value, **kwargs)
        produce_with_new_relic(value, **kwargs) do |headers|
          kwargs[:headers] = headers
          super
        end
      end
    end
  end

  module RubyKafkaConsumer
    module Prepend
      include NewRelic::Agent::Instrumentation::RubyKafka

      def each_message(*args)
        super do |message|
          each_message_with_new_relic(message) do
            yield(message)
          end
        end
      end
    end
  end

  module RubyKafkaClient
    module Prepend
      include NewRelic::Agent::Instrumentation::RubyKafkaConfig

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
