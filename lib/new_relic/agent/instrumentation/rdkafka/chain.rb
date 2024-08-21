# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Rdkafka::Chain
    def self.instrument!
      ::Rdkafka::Producer.class_eval do
        include NewRelic::Agent::Instrumentation::Rdkafka

        alias_method(:produce_without_new_relic, :produce)

        def produce(**kwargs)
          produce_with_new_relic(kwargs) do |headers|
            kwargs[:headers] = headers
            produce_without_new_relic(**kwargs)
          end
        end
      end

      ::Rdkafka::Consumer.class_eval do
        include NewRelic::Agent::Instrumentation::Rdkafka

        alias_method(:each_without_new_relic, :each)

        def each(**kwargs)
          each_without_new_relic(**kwargs) do |message|
            each_with_new_relic(message) do
              yield(message)
            end
          end
        end
      end

      ::Rdkafka::Config.class_eval do
        include NewRelic::Agent::Instrumentation::RdkafkaConfig

        alias_method(:producer_without_new_relic, :producer)

        def producer(**kwargs)
          producer_without_new_relic(**kwargs).tap do |producer|
            set_nr_config(producer)
          end
        end

        alias_method(:consumer_without_new_relic, :consumer)

        def consumer(**kwargs)
          consumer_without_new_relic(**kwargs).tap do |consumer|
            set_nr_config(consumer)
          end
        end
      end
    end
  end
end
