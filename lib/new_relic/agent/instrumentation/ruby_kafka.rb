# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'ruby_kafka/instrumentation'
require_relative 'ruby_kafka/chain'
require_relative 'ruby_kafka/prepend'

DependencyDetection.defer do
  named :'ruby_kafka'

  depends_on do
    defined?(Kafka)
  end

  executes do
    NewRelic::Agent.logger.info('Installing ruby-kafka instrumentation')

    if use_prepend?
      prepend_instrument Kafka::Producer, NewRelic::Agent::Instrumentation::RubyKafkaProducer::Prepend
      prepend_instrument Kafka::Consumer, NewRelic::Agent::Instrumentation::RubyKafkaConsumer::Prepend
      prepend_instrument Kafka::Client, NewRelic::Agent::Instrumentation::RubyKafkaClient::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::RubyKafka::Chain
    end
  end
end
