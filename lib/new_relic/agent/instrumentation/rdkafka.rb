# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'rdkafka/instrumentation'
require_relative 'rdkafka/chain'
require_relative 'rdkafka/prepend'

DependencyDetection.defer do
  named :rdkafka

  depends_on do
    defined?(Rdkafka)
  end

  executes do
    NewRelic::Agent.logger.info('Installing rdkafka instrumentation')

    if use_prepend?
      prepend_instrument Rdkafka::Config, NewRelic::Agent::Instrumentation::RdkafkaConfig::Prepend
      prepend_instrument Rdkafka::Producer, NewRelic::Agent::Instrumentation::RdkafkaProducer::Prepend
      prepend_instrument Rdkafka::Consumer, NewRelic::Agent::Instrumentation::RdkafkaConsumer::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::Rdkafka::Chain
    end
  end
end
