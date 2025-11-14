# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module RubyKafka::Chain
    def self.instrument!
      ::Kafka::Producer.class_eval do
        include NewRelic::Agent::Instrumentation::RubyKafka

        alias_method(:produce_without_new_relic, :produce)

        def produce(value, **kwargs)
          produce_with_new_relic(value, **kwargs) do |headers|
            kwargs[:headers] = headers
            produce_without_new_relic(value, **kwargs)
          end
        end
      end

      ::Kafka::Consumer.class_eval do
        include NewRelic::Agent::Instrumentation::RubyKafka

        alias_method(:each_message_without_new_relic, :each_message)

        def each_message(*args)
          each_message_without_new_relic(*args) do |message|
            each_message_with_new_relic(message) do
              yield(message)
            end
          end
        end
      end

      ::Kafka::Client.class_eval do
        include NewRelic::Agent::Instrumentation::RubyKafkaConfig

        alias_method(:producer_without_new_relic, :producer)
        alias_method(:consumer_without_new_relic, :consumer)

        def producer(**kwargs)
          producer_without_new_relic(**kwargs).tap do |producer|
            set_nr_config(producer)
          end
        end

        def consumer(**kwargs)
          consumer_without_new_relic(**kwargs).tap do |consumer|
            set_nr_config(consumer)
          end
        end
      end
    end
  end
end
